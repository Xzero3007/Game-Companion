//! Global shortcuts through the desktop's GlobalShortcuts portal
//! (`org.freedesktop.portal.GlobalShortcuts`).
//!
//! Wayland lets no app grab keys itself: the app asks the desktop for named
//! shortcuts and suggests keys. KDE Plasma asks the user once to confirm them
//! and keeps them in System Settings → Keyboard → Shortcuts, where they can be
//! changed. Adapted from the Clicktrough meter's `hotkeys.rs` (GPL-3.0); the
//! overlay holds no special permissions, so it talks to the portal itself
//! instead of through a helper process.
//!
//! Everything here is local D-Bus on this computer: nothing leaves it.

use std::collections::HashMap;

use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::{ObjectPath, OwnedValue, Value};

const PORTAL: &str = "org.freedesktop.portal.Desktop";
const PORTAL_PATH: &str = "/org/freedesktop/portal/desktop";
const SHORTCUTS: &str = "org.freedesktop.portal.GlobalShortcuts";
/// The app id the desktop files the shortcuts under; the desktop file has it
/// as its name.
pub const APP_ID: &str = "io.github.xzero3007.GameCompanion";

/// A shortcut the overlay asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Shortcut {
    /// Stable id: the desktop keeps the user's key under it.
    pub id: &'static str,
    pub description: &'static str,
    /// The suggested key, in the portal's form (`CTRL+ALT+o`).
    pub trigger: &'static str,
}

/// The overlay's shortcuts. Brave and Legcord get theirs once they are built.
pub const ALL: [Shortcut; 2] = [
    Shortcut { id: "lock", description: "Lock or unlock the overlay (locked, clicks go to the game)", trigger: "ALT+q" },
    Shortcut { id: "toggle", description: "Hide or show the hub (pinned things stay)", trigger: "ALT+y" },
];

/// What the desktop said about one shortcut.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Bound, to this key as the desktop describes it.
    Bound(Option<String>),
    /// Registered, but the desktop gave it no key (taken, or the dialog closed).
    NoKey,
    /// No portal, or the user refused: there are no shortcuts.
    Unavailable(String),
}

/// Registers the shortcuts and calls `fire` with each activated shortcut's id
/// until the session bus closes. Blocks: run it on its own thread.
pub fn listen(status: impl Fn(&str, Status), fire: impl Fn(&str)) {
    if let Err(e) = bind_and_wait(&status, &fire) {
        let reason = e.to_string();
        for s in ALL {
            status(s.id, Status::Unavailable(reason.clone()));
        }
    }
}

fn proxy<'a>(connection: &Connection, path: &'a str, interface: &'a str) -> zbus::Result<Proxy<'a>> {
    Proxy::new(connection, PORTAL, path, interface)
}

fn bind_and_wait(status: &dyn Fn(&str, Status), fire: &dyn Fn(&str)) -> zbus::Result<()> {
    let connection = Connection::session()?;

    // An unsandboxed app says who it is before any other portal call, so the
    // desktop files the shortcuts under Game Companion. Portals before 1.19
    // have no registry: carry on without.
    let no_options: HashMap<&str, Value> = HashMap::new();
    if let Ok(registry) = proxy(&connection, PORTAL_PATH, "org.freedesktop.host.portal.Registry") {
        let _ = registry.call::<_, _, ()>("Register", &(APP_ID, no_options));
    }

    let portal = proxy(&connection, PORTAL_PATH, SHORTCUTS)?;
    // Listen before binding, so no activation is missed.
    let activations = portal.receive_signal("Activated")?;

    let mut options: HashMap<&str, Value> = HashMap::new();
    options.insert("handle_token", Value::from("gc_session_req"));
    options.insert("session_handle_token", Value::from("gc_session"));
    let (code, results) = request(&connection, &portal, "gc_session_req", "CreateSession", &(options,))?;
    if code != 0 {
        return Err(zbus::Error::Failure(format!("the desktop refused a shortcut session ({code})")));
    }
    let session: String = results
        .get("session_handle")
        .and_then(|v| v.downcast_ref::<&str>().ok().map(str::to_string))
        .ok_or_else(|| zbus::Error::Failure("the desktop gave no shortcut session".into()))?;
    let session_path = ObjectPath::try_from(session.as_str())?;

    let shortcuts: Vec<(&str, HashMap<&str, Value>)> = ALL
        .iter()
        .map(|s| {
            let mut props: HashMap<&str, Value> = HashMap::new();
            props.insert("description", Value::from(s.description));
            props.insert("preferred_trigger", Value::from(s.trigger));
            (s.id, props)
        })
        .collect();
    let mut bind_options: HashMap<&str, Value> = HashMap::new();
    bind_options.insert("handle_token", Value::from("gc_bind_req"));
    let (code, bound) = request(
        &connection,
        &portal,
        "gc_bind_req",
        "BindShortcuts",
        &(&session_path, shortcuts, "", bind_options),
    )?;
    if code != 0 {
        // 1: the user closed the desktop's dialog. Nothing is bound.
        return Err(zbus::Error::Failure(format!("the shortcuts were not confirmed ({code})")));
    }
    match assigned(&bound) {
        Some(list) => {
            for (id, key) in list {
                status(&id, if key.is_some() { Status::Bound(key) } else { Status::NoKey });
            }
        }
        None => {
            for s in ALL {
                status(s.id, Status::Bound(None));
            }
        }
    }

    for message in activations {
        let body = message.body();
        let Ok((from, id, _time, _options)) =
            body.deserialize::<(ObjectPath<'_>, &str, u64, HashMap<&str, OwnedValue>)>()
        else {
            continue;
        };
        if from.as_str() == session_path.as_str() {
            fire(id);
        }
    }
    Ok(())
}

/// Calls a portal method that answers through a Request object's `Response`
/// signal, and waits for it. Returns the response code and results.
fn request<B>(
    connection: &Connection,
    portal: &Proxy<'_>,
    token: &str,
    method: &str,
    body: &B,
) -> zbus::Result<(u32, HashMap<String, OwnedValue>)>
where
    B: serde::Serialize + zbus::zvariant::DynamicType,
{
    // The request's path is known in advance: subscribe before calling, so a
    // quick answer is not missed.
    let sender = connection
        .unique_name()
        .ok_or_else(|| zbus::Error::Failure("no unique bus name".into()))?
        .trim_start_matches(':')
        .replace('.', "_");
    let path = format!("/org/freedesktop/portal/desktop/request/{sender}/{token}");
    let request = proxy(connection, &path, "org.freedesktop.portal.Request")?;
    let mut responses = request.receive_signal("Response")?;
    let _handle: zbus::zvariant::OwnedObjectPath = portal.call(method, body)?;
    let message = responses
        .next()
        .ok_or_else(|| zbus::Error::Failure(format!("no answer to {method}")))?;
    let (code, results): (u32, HashMap<String, OwnedValue>) = message.body().deserialize()?;
    Ok((code, results))
}

/// Which shortcuts the desktop gave a key, from BindShortcuts' `shortcuts`
/// result (`a(sa{sv})`, each with its `trigger_description`).
fn assigned(results: &HashMap<String, OwnedValue>) -> Option<Vec<(String, Option<String>)>> {
    let list = results.get("shortcuts")?;
    let array = list.downcast_ref::<zbus::zvariant::Array>().ok()?;
    let mut out = Vec::new();
    for item in array.iter() {
        let Value::Structure(entry) = item else { continue };
        let fields = entry.fields();
        let Some(Value::Str(id)) = fields.first() else { continue };
        let Some(Value::Dict(props)) = fields.get(1) else { continue };
        let described = props
            .get::<&str, Value>(&"trigger_description")
            .ok()
            .flatten()
            .and_then(|v| text_of(&v));
        out.push((id.as_str().to_string(), described));
    }
    Some(out)
}

fn text_of(value: &Value) -> Option<String> {
    match value {
        Value::Str(s) => Some(s.as_str().trim().to_string()).filter(|t| !t.is_empty()),
        Value::Value(inner) => text_of(inner),
        _ => None,
    }
}

/// The suggested key as people write it (`CTRL+ALT+o` → `Ctrl+Alt+O`).
pub fn readable(trigger: &str) -> String {
    trigger
        .split('+')
        .map(|part| match part {
            "CTRL" => "Ctrl".to_string(),
            "ALT" => "Alt".to_string(),
            "SHIFT" => "Shift".to_string(),
            "LOGO" | "SUPER" => "Meta".to_string(),
            key => key.to_uppercase(),
        })
        .collect::<Vec<_>>()
        .join("+")
}

/// Opens KDE's shortcut settings (local programs only), where the user
/// changes the keys. Returns whether one started.
pub fn open_desktop_settings() -> bool {
    use std::process::Command;
    [&["systemsettings", "kcm_keys"][..], &["kcmshell6", "kcm_keys"][..]]
        .iter()
        .any(|args| Command::new(args[0]).args(&args[1..]).spawn().is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn readable_keys() {
        assert_eq!(readable("CTRL+ALT+o"), "Ctrl+Alt+O");
        assert_eq!(readable("ALT+q"), "Alt+Q");
        assert_eq!(readable("ALT+y"), "Alt+Y");
    }

    #[test]
    fn ids_are_unique_and_keys_differ_from_the_meter() {
        // The meter uses Ctrl+Alt+R and Ctrl+Alt+arrows.
        let ids: std::collections::HashSet<_> = ALL.iter().map(|s| s.id).collect();
        assert_eq!(ids.len(), ALL.len());
        for s in ALL {
            assert!(!s.trigger.ends_with("+r") && !s.trigger.contains("Up") && !s.trigger.contains("Down"));
        }
    }
}
