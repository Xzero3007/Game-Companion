//! Proton downloads for QML (the `ProtonGet` singleton; the logic is
//! `proton_get`). The Proton overview asks `look` when it opens; nothing
//! runs while it is closed and no download is going on.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::Ordering;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::proton_get::{self as pg, Flavour, Kept, Step};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        /// Everything the panel shows, as JSON: `flavours` (each with its
        /// latest release, notes, the games it names, the installed
        /// downloads), `targets`, `pacman`, `job`, `checking`, `error`,
        /// `checkedAt`.
        #[qproperty(QString, state)]
        /// Goes up when a Proton was installed or removed (the overview
        /// reads the installed builds again).
        #[qproperty(i32, revision)]
        /// Steam restarts by itself after an install (settings
        /// `proton_restart_steam`; never while a game runs).
        #[qproperty(bool, restart_after)]
        type ProtonGet = super::ProtonGetRust;

        /// Looks for new releases (GitHub at most every 6 hours unless
        /// `force`) and reads what is installed. `games`: the library's
        /// names as a JSON list, to find them in the release notes.
        #[qinvokable]
        fn look(self: Pin<&mut ProtonGet>, force: bool, games: &QString);

        /// Downloads and installs a flavour's latest release ("ge" or
        /// "cachyos") for a target ("steam" or "heroic").
        #[qinvokable]
        fn install(self: Pin<&mut ProtonGet>, flavour: &QString, target: &QString);

        /// Keeps whether Steam restarts after an install.
        #[qinvokable]
        fn set_restart(self: Pin<&mut ProtonGet>, on: bool);

        /// Restarts Steam now (the button after an install).
        #[qinvokable]
        fn restart_steam(self: Pin<&mut ProtonGet>);

        /// Stops the running download.
        #[qinvokable]
        fn cancel(self: Pin<&mut ProtonGet>);

        /// Removes a downloaded Proton folder (asked first in the panel).
        #[qinvokable]
        fn remove(self: Pin<&mut ProtonGet>, path: &QString);

        /// Opens a release's page on GitHub in the browser.
        #[qinvokable]
        fn open_release(self: Pin<&mut ProtonGet>, url: &QString) -> bool;

        /// Forgets a finished job's note.
        #[qinvokable]
        fn dismiss(self: Pin<&mut ProtonGet>);
    }

    impl cxx_qt::Threading for ProtonGet {}
}

pub struct ProtonGetRust {
    state: QString,
    revision: i32,
    restart_after: bool,
    base: Value,
    job: Value,
    checking: bool,
    error: String,
    games: Vec<String>,
}

impl Default for ProtonGetRust {
    fn default() -> Self {
        Self {
            state: QString::from("{}"),
            revision: 0,
            restart_after: crate::settings::read(|s| s.proton_restart_steam),
            base: json!({}), job: Value::Null, checking: false, error: String::new(),
            games: Vec::new(),
        }
    }
}

fn demo() -> Option<String> {
    std::env::var("GC_DEMO").ok().filter(|d| d.split(',').any(|p| p == "games") && d.contains("proton"))
}

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from).filter(|p| p.is_absolute())
}

fn steam_running() -> bool {
    pg::steam_running(Path::new("/proc"))
}

impl qobject::ProtonGet {
    fn publish(mut self: Pin<&mut Self>) {
        let mut v = self.rust().base.clone();
        if !v.is_object() {
            v = json!({});
        }
        v["job"] = self.rust().job.clone();
        v["checking"] = json!(self.rust().checking);
        v["error"] = json!(self.rust().error);
        self.as_mut().set_state(QString::from(&v.to_string()));
    }

    fn look(mut self: Pin<&mut Self>, force: bool, games: &QString) {
        self.as_mut().rust_mut().games = serde_json::from_str(&games.to_string()).unwrap_or_default();
        if self.rust().checking {
            return;
        }
        if let Some(d) = demo() {
            let base = demo_base(&self.rust().games);
            self.as_mut().rust_mut().base = base;
            if d.contains("protonjob") {
                self.as_mut().rust_mut().job = json!({"flavour": "ge", "tag": "GE-Proton11-12", "target": "steam", "step": "download", "done": 262_144_000u64, "total": 498_073_600u64});
            }
            self.publish();
            return;
        }
        self.as_mut().rust_mut().checking = true;
        self.as_mut().rust_mut().error.clear();
        self.as_mut().publish();
        let games = self.rust().games.clone();
        let busy = matches!(self.rust().job["step"].as_str(), Some("download" | "check" | "unpack" | "steam"));
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("proton-look".into())
            .spawn(move || {
                let (base, error) = read_state(force, &games, busy);
                let _ = thread.queue(move |mut obj: Pin<&mut qobject::ProtonGet>| {
                    obj.as_mut().rust_mut().base = base;
                    obj.as_mut().rust_mut().checking = false;
                    obj.as_mut().rust_mut().error = error;
                    obj.publish();
                });
            })
            .ok();
    }

    fn install(mut self: Pin<&mut Self>, flavour: &QString, target: &QString) {
        let job = &self.rust().job;
        if !job.is_null() && matches!(job["step"].as_str(), Some("download" | "check" | "unpack" | "steam")) {
            return;
        }
        let Some(flavour) = Flavour::from_id(&flavour.to_string()) else { return };
        let target_id = target.to_string();
        let Some(home) = home() else { return };
        let Some(target) = pg::targets(&home).into_iter().find(|t| t.id == target_id) else { return };
        let release = pg::KEPT.lock().unwrap_or_else(|p| p.into_inner()).as_ref().and_then(|k| {
            let v3 = cpu_v3();
            k.lists.iter().find(|(f, _)| *f == flavour).and_then(|(_, l)| l.iter().find(|r| pg::pick_asset(flavour, r, v3).is_some()).cloned())
        });
        let Some(release) = release else { return };
        let total = pg::pick_asset(flavour, &release, cpu_v3()).map(|(a, _)| a.size).unwrap_or(0);
        self.as_mut().rust_mut().job = json!({"flavour": flavour.id(), "tag": release.tag, "target": target.id, "step": "download", "done": 0, "total": total});
        self.as_mut().publish();
        pg::RAN.store(true, Ordering::SeqCst);
        crate::log::write("proton", &format!("{}: installing {} for {}", flavour.id(), release.tag, target.id));
        let thread = self.qt_thread();
        let tag = release.tag.clone();
        let restart = *self.restart_after();
        let spawned = std::thread::Builder::new().name("proton-get".into()).spawn(move || {
            let mut last = Step::Check;
            let mut tell = |step: Step| {
                if step == last {
                    return;
                }
                last = step.clone();
                let v = match step {
                    Step::Download { done, total } => json!({"step": "download", "done": done, "total": total}),
                    Step::Check => json!({"step": "check"}),
                    Step::Unpack => json!({"step": "unpack"}),
                    Step::Steam => json!({"step": "steam"}),
                };
                let _ = thread.queue(move |mut obj: Pin<&mut qobject::ProtonGet>| {
                    let job = &mut obj.as_mut().rust_mut().job;
                    if let (Some(job), Some(v)) = (job.as_object_mut(), v.as_object()) {
                        for (k, x) in v {
                            job.insert(k.clone(), x.clone());
                        }
                    }
                    obj.publish();
                });
            };
            let result = pg::install(flavour, &release, &target, cpu_v3(), &mut tell);
            let steam = target.id == "steam" && steam_running();
            // Steam restarted so it sees the new build (not while a game runs).
            let restarted = if result.is_ok() && steam && restart && !pg::steam_game_running(Path::new("/proc")) {
                tell(Step::Steam);
                Some(pg::restart_steam(&home))
            } else {
                None
            };
            let restart_note = match &restarted {
                Some(Ok(true)) => "restarted".to_string(),
                Some(Ok(false)) | None => String::new(),
                Some(Err(why)) => why.clone(),
            };
            let steam = steam && !matches!(restarted, Some(Ok(_)));
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::ProtonGet>| {
                obj.as_mut().rust_mut().job = match result {
                    Ok(name) => json!({"flavour": flavour.id(), "tag": tag, "target": target.id, "step": "done", "name": name, "steamRunning": steam, "steam": restart_note}),
                    Err(why) if why == "Stopped" => json!({"flavour": flavour.id(), "tag": tag, "target": target.id, "step": "stopped"}),
                    Err(why) => json!({"flavour": flavour.id(), "tag": tag, "target": target.id, "step": "failed", "error": why}),
                };
                let n = *obj.revision() + 1;
                obj.as_mut().set_revision(n);
                let games = QString::from(&serde_json::to_string(&obj.rust().games).unwrap_or_default());
                obj.as_mut().publish();
                obj.look(false, &games);
            });
        });
        if spawned.is_err() {
            self.as_mut().rust_mut().job = Value::Null;
            self.publish();
        }
    }

    fn set_restart(mut self: Pin<&mut Self>, on: bool) {
        crate::settings::change(|s| s.proton_restart_steam = on);
        self.as_mut().set_restart_after(on);
    }

    fn restart_steam(mut self: Pin<&mut Self>) {
        if demo().is_some() || !matches!(self.rust().job["step"].as_str(), Some("done")) {
            return;
        }
        let Some(home) = home() else { return };
        self.as_mut().rust_mut().job["step"] = json!("steam");
        self.as_mut().publish();
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("proton-steam".into())
            .spawn(move || {
                let result = pg::restart_steam(&home);
                let _ = thread.queue(move |mut obj: Pin<&mut qobject::ProtonGet>| {
                    let job = &mut obj.as_mut().rust_mut().job;
                    job["step"] = json!("done");
                    match result {
                        Ok(_) => {
                            job["steam"] = json!("restarted");
                            job["steamRunning"] = json!(false);
                        }
                        Err(why) => job["steam"] = json!(why),
                    }
                    obj.publish();
                });
            })
            .ok();
    }

    fn cancel(self: Pin<&mut Self>) {
        pg::cancel();
    }

    fn dismiss(mut self: Pin<&mut Self>) {
        if matches!(self.rust().job["step"].as_str(), Some("done" | "failed" | "stopped")) {
            self.as_mut().rust_mut().job = Value::Null;
            self.publish();
        }
    }

    fn remove(mut self: Pin<&mut Self>, path: &QString) {
        if demo().is_some() {
            return;
        }
        let path = PathBuf::from(path.to_string());
        let Some(home) = home() else { return };
        let thread = self.qt_thread();
        self.as_mut().rust_mut().checking = true;
        self.as_mut().publish();
        std::thread::Builder::new()
            .name("proton-remove".into())
            .spawn(move || {
                let targets = pg::targets(&home);
                let result = if !pg::removable(&targets, &path) {
                    Err("This folder isn't a downloaded Proton".to_string())
                } else {
                    std::fs::remove_dir_all(&path).map_err(|e| e.to_string())
                };
                let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                match &result {
                    Ok(()) => {
                        pg::TOOLS_STALE.store(true, Ordering::SeqCst);
                        crate::log::write("proton", &format!("removed {name}"));
                    }
                    Err(why) => crate::log::write("proton", &format!("{name} not removed: {why}")),
                }
                let _ = thread.queue(move |mut obj: Pin<&mut qobject::ProtonGet>| {
                    obj.as_mut().rust_mut().checking = false;
                    if result.is_ok() {
                        let n = *obj.revision() + 1;
                        obj.as_mut().set_revision(n);
                    }
                    let games = QString::from(&serde_json::to_string(&obj.rust().games).unwrap_or_default());
                    obj.as_mut().look(false, &games);
                    if let Err(why) = result {
                        obj.as_mut().rust_mut().error = format!("Couldn't remove {name}: {why}");
                        obj.publish();
                    }
                });
            })
            .ok();
    }

    fn open_release(self: Pin<&mut Self>, url: &QString) -> bool {
        pg::open_page(&url.to_string()).is_ok()
    }
}

fn cpu_v3() -> bool {
    pg::cpu_v3(&std::fs::read_to_string("/proc/cpuinfo").unwrap_or_default())
}

/// Reads the release lists (GitHub if they are older than 6 hours, or
/// `force`) and what is installed, as the panel's JSON.
fn read_state(force: bool, games: &[String], busy: bool) -> (Value, String) {
    let Some(home) = home() else { return (json!({}), "No home folder".into()) };
    let targets = pg::targets(&home);
    // What a crash or a kill left (no job runs now).
    if !busy {
        pg::tidy_leftovers(&targets);
        pg::tidy_downloads();
    }
    let mut error = String::new();
    {
        let mut kept = pg::KEPT.lock().unwrap_or_else(|p| p.into_inner());
        if kept.is_none() {
            *kept = pg::load_kept();
        }
        let old = kept.as_ref().is_none_or(|k| pg::now().saturating_sub(k.at) > pg::KEEP_LIST.as_secs());
        if force || old {
            let mut lists = Vec::new();
            for f in Flavour::ALL {
                match pg::fetch_releases(f) {
                    Ok(list) => lists.push((f, list)),
                    Err(why) => {
                        error = why;
                        if let Some(prev) = kept.as_ref().and_then(|k| k.lists.iter().find(|(g, _)| *g == f)) {
                            lists.push(prev.clone());
                        }
                    }
                }
            }
            if error.is_empty() {
                crate::log::write("proton", "release lists read from GitHub");
            }
            let at = if error.is_empty() { pg::now() } else { kept.as_ref().map(|k| k.at).unwrap_or(0) };
            let k = Kept { at, lists };
            if error.is_empty() {
                pg::save_kept(&k);
            }
            *kept = Some(k);
        }
    }
    let kept = pg::KEPT.lock().unwrap_or_else(|p| p.into_inner());
    let installed = pg::installed(&targets);
    let lists: Vec<(Flavour, Vec<pg::Release>)> = kept.as_ref().map(|k| k.lists.clone()).unwrap_or_default();
    let at = kept.as_ref().map(|k| k.at).unwrap_or(0);
    drop(kept);
    let mut base = state_json(&lists, &installed, &targets, games, cpu_v3());
    base["checkedAt"] = json!(at);
    base["pacman"] = Value::Array(pg::pacman_notes());
    (base, error)
}

/// The panel's JSON from the release lists and what is installed.
pub fn state_json(lists: &[(Flavour, Vec<pg::Release>)], installed: &[pg::Installed], targets: &[pg::Target], games: &[String], v3: bool) -> Value {
    let flavours: Vec<Value> = Flavour::ALL
        .into_iter()
        .map(|f| {
            let mine: Vec<&pg::Installed> = installed.iter().filter(|i| i.flavour == f).collect();
            let best = mine.iter().filter_map(|i| pg::version_key(f, &i.name)).max();
            let releases: &[pg::Release] = lists.iter().find(|(g, _)| *g == f).map(|(_, l)| l.as_slice()).unwrap_or(&[]);
            let latest = releases.iter().find(|r| pg::pick_asset(f, r, v3).is_some());
            let latest_key = latest.and_then(|r| pg::version_key(f, &r.tag));
            let newer = matches!((latest_key, best), (Some(l), Some(b)) if l > b);
            // Notes of every release since the installed one name the games.
            let since: Vec<&pg::Release> =
                releases.iter().filter(|r| best.is_none_or(|b| pg::version_key(f, &r.tag).is_some_and(|k| k > b))).take(8).collect();
            let named = pg::mentions(&since.iter().map(|r| r.body.as_str()).collect::<Vec<_>>().join("\n"), games);
            let have_latest = latest_key.is_some() && best == latest_key;
            json!({
                "id": f.id(),
                "title": f.title(),
                "about": f.about(),
                "latest": latest.map(|r| {
                    let asset = pg::pick_asset(f, r, v3).map(|(a, _)| a);
                    json!({
                        "tag": r.tag, "name": r.name, "date": r.published.get(..10).unwrap_or(""), "page": r.page,
                        "notes": pg::notes_text(&r.body, 1400), "size": asset.as_ref().map(|a| a.size).unwrap_or(0),
                        "file": asset.map(|a| a.name).unwrap_or_default(),
                    })
                }),
                "newer": newer,
                "haveLatest": have_latest,
                "since": since.len(),
                "named": named,
                "installed": mine.iter().map(|i| {
                    let key = pg::version_key(f, &i.name);
                    // Its own release's notes (MN, 0.8.70), when the kept list has it.
                    let own = key.and_then(|k| releases.iter().find(|r| pg::version_key(f, &r.tag) == Some(k)));
                    json!({
                        "name": i.name, "path": i.path.to_string_lossy(), "target": i.target,
                        "latest": latest_key.is_some() && key == latest_key,
                        "tag": own.map(|r| r.tag.as_str()).unwrap_or(""),
                        "date": own.and_then(|r| r.published.get(..10)).unwrap_or(""),
                        "page": own.map(|r| r.page.as_str()).unwrap_or(""),
                        "notes": own.map(|r| pg::notes_text(&r.body, 1400)).unwrap_or_default(),
                    })
                }).collect::<Vec<_>>(),
            })
        })
        .collect();
    json!({
        "flavours": flavours,
        "targets": targets.iter().map(|t| json!({"id": t.id, "label": t.label, "dir": tilde(&t.dir)})).collect::<Vec<_>>(),
    })
}

fn tilde(path: &Path) -> String {
    let text = path.to_string_lossy().into_owned();
    match home() {
        Some(h) => match text.strip_prefix(&*h.to_string_lossy()) {
            Some(rest) => format!("~{rest}"),
            None => text,
        },
        None => text,
    }
}

/// Screenshots (GC_DEMO=games,proton): made-up releases and installs.
fn demo_base(games: &[String]) -> Value {
    let rel = |f: Flavour, tag: &str, file: &str, body: &str, date: &str| pg::Release {
        tag: tag.into(),
        name: format!("{tag} Released"),
        published: date.into(),
        body: body.into(),
        page: format!("https://github.com/{}/releases/tag/{tag}", f.repo()),
        assets: vec![pg::Asset { name: file.into(), url: String::new(), size: 498_073_600, digest: Some("sha256:00".into()) }],
    };
    let lists = vec![
        (
            Flavour::Ge,
            vec![
                rel(Flavour::Ge, "GE-Proton11-12", "GE-Proton11-12.tar.gz", "## Changes\n- Wine updated to the latest bleeding edge\n- DXVK and VKD3D-Proton updated\n- Fixed Path of Exile 2 stutter when loading areas\n- Fixed video playback in Space Game", "2026-11-03T07:19:00Z"),
                rel(Flavour::Ge, "GE-Proton11-11", "GE-Proton11-11.tar.gz", "- Fixed AION 2 launcher", "2026-10-19T18:20:00Z"),
            ],
        ),
        (
            Flavour::Cachy,
            vec![rel(Flavour::Cachy, "cachyos-11.0-20261015-slr", "proton-cachyos-11.0-20261015-slr-x86_64_v3.tar.xz", "- Rebased on Proton 11.0\n- NTSync on by default\n- FSR 4 upgrade fixes", "2026-10-20T21:21:00Z")],
        ),
    ];
    let mut installed = vec![
        pg::Installed { flavour: Flavour::Ge, name: "GE-Proton10-25".into(), path: "/home/me/.local/share/Steam/compatibilitytools.d/GE-Proton10-25".into(), target: "steam" },
        pg::Installed { flavour: Flavour::Ge, name: "GE-Proton9-20".into(), path: "/home/me/.local/share/Steam/compatibilitytools.d/GE-Proton9-20".into(), target: "steam" },
    ];
    // GC_DEMO=games,proton,protonmany: a long list as on MN's computer.
    if demo().is_some_and(|d| d.contains("protonmany")) {
        let steam = ["GE-Proton11-12-x86_64", "GE-Proton11-7-x86_64", "GE-Proton11-1", "proton-cachyos-10.0-20260330-slr-x86_64_v3",
            "proton-cachyos-10.0-20260424-slr-x86_64_v3", "proton-cachyos-10.0-sunset-slr-x86_64_v3", "proton-cachyos-11.0-20260506-slr-x86_64",
            "proton-cachyos-11.0-20260506-slr-x86_64_v3", "proton-cachyos-11.0-20261015-slr-x86_64_v3", "proton-cachyos-11.0-20260601-slr-x86_64_v3"];
        for (target, names) in [("steam", &steam[..]), ("heroic", &["proton-cachyos-11.0-20260602-slr-x86_64_v3", "proton-cachyos-11.0-20260702-slr-x86_64_v3"][..])] {
            for n in names {
                let flavour = if n.starts_with("GE") { Flavour::Ge } else { Flavour::Cachy };
                installed.push(pg::Installed { flavour, name: (*n).into(), path: format!("/demo/{target}/{n}").into(), target });
            }
        }
    }
    let targets = vec![
        pg::Target { id: "steam", label: "Steam", dir: "~/.local/share/Steam/compatibilitytools.d".into() },
        pg::Target { id: "heroic", label: "Heroic", dir: "~/.config/heroic/tools/proton".into() },
    ];
    pg::sort_installed(&mut installed, &targets);
    let mut base = state_json(&lists, &installed, &targets, games, true);
    base["checkedAt"] = json!(pg::now() - 3600);
    base["pacman"] = json!([{"pkg": "proton-cachyos-slr", "have": "1:11.0.20261014-1", "repo": "1:11.0.20261015-1", "newer": true}]);
    base
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newer_and_named_games() {
        let v = demo_base(&["Path of Exile 2".into(), "AION 2".into(), "Space Game".into()]);
        let ge = &v["flavours"][0];
        assert_eq!(ge["newer"], true);
        assert_eq!(ge["since"], 2);
        assert_eq!(ge["named"], json!(["Path of Exile 2", "AION 2", "Space Game"]));
        assert_eq!(ge["latest"]["date"], "2026-11-03");
        let cachy = &v["flavours"][1];
        assert_eq!(cachy["newer"], false, "nothing installed: not 'newer', just installable");
        assert!(cachy["installed"].as_array().unwrap().is_empty());
    }
}
