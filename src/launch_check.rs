//! Checks launch options against what is known about them
//! (`data/launch-options.json`, compiled in): per word a status (`ok`,
//! `outdated`, `invalid`, `no_effect`, `not_recommended`, `unknown`), a
//! plain explanation and, where one exists, a fix. What an option does
//! depends on the game's Proton build ("flavour"): Valve's, Experimental,
//! GE-Proton, proton-cachyos, Wine (Lutris/Heroic) or a native Linux game.
//!
//! Only the compiled-in list is read; the source documents named in it
//! are never fetched.

use std::collections::BTreeMap;
use std::sync::OnceLock;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::launch_options::{self, Current, Flavour, Tool};
use crate::system_info::SystemInfo;

// ---------------------------------------------------------- knowledge ----

#[derive(Debug, Deserialize)]
pub struct Kb {
    pub sources: BTreeMap<String, String>,
    pub entries: Vec<Entry>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub name: String,
    #[serde(default)]
    pub aliases: Vec<String>,
    /// "env", "wrapper" or "arg".
    pub kind: String,
    /// `name` is a prefix (`DXVK_NVAPI_DRS_`).
    #[serde(default)]
    pub prefix: bool,
    #[serde(default)]
    pub value: ValueSpec,
    pub flavours: Vec<String>,
    /// current, retired, discouraged, experimental, debug, unverified.
    pub status: String,
    #[serde(default)]
    pub replacement: String,
    #[serde(default)]
    pub since: String,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub warning: String,
    /// "nvidia", "amd", "intel" or "".
    #[serde(default)]
    pub vendor: String,
    /// The program a wrapper needs (checked against the tools found).
    #[serde(default)]
    pub tool: String,
    /// Only inside Steam's runtime container (pressure-vessel).
    #[serde(default)]
    pub container: bool,
    #[serde(default)]
    pub by_flavour: BTreeMap<String, Override>,
    pub explanation: String,
    pub source: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ValueSpec {
    /// any, bool, enum, flags, number, version, size, path, hidraw,
    /// dll_overrides, dxvk_config ("" = no value).
    #[serde(rename = "type", default)]
    pub kind: String,
    #[serde(default)]
    pub values: Vec<String>,
    #[serde(default)]
    pub separator: String,
    pub min: Option<f64>,
    pub max: Option<f64>,
    /// A flag's own explanation.
    #[serde(default)]
    pub notes: BTreeMap<String, String>,
    /// Flags seen in use that no source confirms.
    #[serde(default)]
    pub uncertain: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Override {
    pub status: String,
    /// Only from this Valve major on.
    pub from: Option<u32>,
    #[serde(default)]
    pub since: String,
    #[serde(default)]
    pub replacement: String,
    #[serde(default)]
    pub note: String,
}

pub fn kb() -> &'static Kb {
    static KB: OnceLock<Kb> = OnceLock::new();
    KB.get_or_init(|| serde_json::from_str(include_str!("../data/launch-options.json")).expect("data/launch-options.json"))
}

impl Entry {
    fn names(&self) -> impl Iterator<Item = &str> {
        std::iter::once(self.name.as_str()).chain(self.aliases.iter().map(String::as_str))
    }

    fn matches(&self, kind: &str, name: &str) -> bool {
        self.kind == kind && (self.names().any(|n| n == name) || (self.prefix && name.starts_with(&self.name) && name.len() > self.name.len()))
    }

    /// The flavours it works with, shorthands spelt out.
    pub fn flavour_names(&self) -> Vec<&'static str> {
        let mut out: Vec<&'static str> = Vec::new();
        for f in &self.flavours {
            let add: &[&'static str] = match f.as_str() {
                "proton" => &PROTONS,
                "dxvk" => &["valve", "experimental", "ge", "cachyos", "wine"],
                "all" => &ALL,
                other => match ALL.iter().find(|a| **a == other) {
                    Some(a) => std::slice::from_ref(a),
                    None => &[],
                },
            };
            for a in add {
                if !out.contains(a) {
                    out.push(a);
                }
            }
        }
        out
    }

    fn source_text(&self) -> String {
        let sources = &kb().sources;
        self.source
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|s| sources.get(s).cloned().unwrap_or_else(|| s.to_string()))
            .collect::<Vec<_>>()
            .join("; ")
    }
}

const PROTONS: [&str; 4] = ["valve", "experimental", "ge", "cachyos"];
const ALL: [&str; 6] = ["valve", "experimental", "ge", "cachyos", "wine", "native"];

/// The known entry for a word: an env var by name, a wrapper by program.
pub fn find(kind: &str, name: &str) -> Option<&'static Entry> {
    kb().entries.iter().find(|e| e.matches(kind, name))
}

/// Flavour names for people.
fn flavour_label(f: &str) -> &'static str {
    match f {
        "valve" => "Valve's Proton",
        "experimental" => "Proton Experimental",
        "ge" => "GE-Proton",
        "cachyos" => "proton-cachyos",
        "wine" => "Wine",
        "native" => "native Linux games",
        _ => "Proton",
    }
}

fn list_label(list: &[&str]) -> String {
    let labels: Vec<&str> = list.iter().map(|f| flavour_label(f)).collect();
    match labels.as_slice() {
        [] => String::new(),
        [one] => one.to_string(),
        [rest @ .., last] => format!("{} and {last}", rest.join(", ")),
    }
}

// ------------------------------------------------------------ context ----

/// The family of the build a game runs on.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Family {
    /// Valve's numbered Proton (major; `NEWEST` for Hotfix).
    Valve(u32),
    Experimental,
    Ge(u32, u32),
    CachyOs,
    /// Some Proton whose family could not be told.
    ProtonOther,
    Wine,
    Native,
}

pub const NEWEST: u32 = u32::MAX;

impl Family {
    pub fn name(self) -> &'static str {
        match self {
            Family::Valve(_) => "valve",
            Family::Experimental => "experimental",
            Family::Ge(..) => "ge",
            Family::CachyOs => "cachyos",
            Family::ProtonOther => "proton",
            Family::Wine => "wine",
            Family::Native => "native",
        }
    }

    pub fn proton(self) -> bool {
        !matches!(self, Family::Wine | Family::Native)
    }

    pub fn from_flavour(f: Flavour) -> Family {
        match f {
            Flavour::Ge(m, r) => Family::Ge(m, r),
            Flavour::CachyOs => Family::CachyOs,
            Flavour::Experimental => Family::Experimental,
            Flavour::Hotfix => Family::Valve(NEWEST),
            Flavour::Valve(m) => Family::Valve(m),
            Flavour::Unknown => Family::ProtonOther,
        }
    }
}

/// What a check needs to know about the game and the computer.
#[derive(Debug, Clone)]
pub struct Ctx {
    pub family: Family,
    /// The build's name as shown ("GE-Proton10-25"), "" when unknown.
    pub tool: String,
    /// The family is known for sure (a Steam game without its own choice
    /// may also be a native one).
    pub sure: bool,
    /// Graphics vendors present ("nvidia", "amd", "intel"); empty = unknown.
    pub gpus: Vec<String>,
    pub nvidia_major: Option<u32>,
    /// Tools found on PATH (of `system_info::TOOLS`).
    pub tools: Vec<String>,
    pub ananicy: bool,
    pub cachyos: bool,
    /// Steam's own launch options: `%command%` matters.
    pub steam_form: bool,
}

impl Ctx {
    pub fn has_gpu(&self, vendor: &str) -> bool {
        self.gpus.iter().any(|g| g == vendor)
    }

    fn has_tool(&self, tool: &str) -> bool {
        self.tools.iter().any(|t| t == tool)
    }

    /// A proton-cachyos build without Steam's runtime container.
    fn outside_container(&self) -> bool {
        self.family == Family::CachyOs && self.tool.to_ascii_lowercase().contains("native")
    }

    pub fn to_json(&self) -> Value {
        json!({
            "flavour": self.family.name(),
            "label": self.tool,
            "sure": self.sure,
            "cachyos": self.cachyos,
        })
    }
}

/// The context of a game: its build's family from its launcher's choice.
pub fn context(sys: &SystemInfo, current: &Current, tools: &[Tool]) -> Ctx {
    let (family, tool, sure) = if current.proton == Some(false) {
        let wine = matches!(current.launcher.as_str(), "lutris" | "heroic")
            || (current.launcher == "own" && current.text.to_ascii_lowercase().split_whitespace().any(|w| w.rsplit('/').next().is_some_and(|p| p.starts_with("wine"))));
        (if wine { Family::Wine } else { Family::Native }, current.tool.clone(), true)
    } else {
        match launch_options::proton_in_use(current, tools) {
            Some((f, label)) => (Family::from_flavour(f), label, current.proton == Some(true)),
            None => (Family::ProtonOther, current.tool.clone(), current.proton == Some(true)),
        }
    };
    Ctx {
        family,
        tool,
        sure,
        gpus: sys.gpus.iter().map(|g| g.vendor.clone()).collect(),
        nvidia_major: sys.nvidia_major(),
        tools: sys.tools.iter().map(|(n, _)| n.clone()).collect(),
        ananicy: sys.ananicy,
        cachyos: sys.cachyos(),
        steam_form: current.launcher != "own",
    }
}

// ------------------------------------------------------------- checks ----

/// One flag of a list value (VKD3D_CONFIG, DXVK_HUD, RADV_PERFTEST).
#[derive(Debug, Clone, PartialEq)]
pub struct FlagCheck {
    pub flag: String,
    pub status: &'static str,
    pub note: String,
    pub suggestion: String,
}

/// One word (or `NAME=value`) of the launch options.
#[derive(Debug, Clone, PartialEq)]
pub struct TokenCheck {
    pub text: String,
    /// "env", "wrapper", "arg", "command" (`%command%` or an own entry's
    /// program).
    pub kind: &'static str,
    pub name: String,
    pub value: String,
    pub status: &'static str,
    pub explanation: String,
    pub note: String,
    pub warning: String,
    /// The option that replaces it ("DXVK_HDR=1"), if any.
    pub replacement: String,
    /// What the word should become ("" = take it out); None = no fix.
    pub fix: Option<String>,
    pub source: String,
    pub flags: Vec<FlagCheck>,
    /// Byte range in the text (for fixes).
    pub span: (usize, usize),
}

impl TokenCheck {
    fn new(text: &str, kind: &'static str, name: &str, value: &str, span: (usize, usize)) -> Self {
        TokenCheck {
            text: text.into(),
            kind,
            name: name.into(),
            value: value.into(),
            status: "ok",
            explanation: String::new(),
            note: String::new(),
            warning: String::new(),
            replacement: String::new(),
            fix: None,
            source: String::new(),
            flags: Vec::new(),
            span,
        }
    }

    fn add_note(&mut self, note: &str) {
        if note.is_empty() || self.note.contains(note) {
            return;
        }
        if !self.note.is_empty() {
            self.note.push(' ');
        }
        self.note.push_str(note);
    }

    pub fn to_json(&self) -> Value {
        json!({
            "text": self.text, "kind": self.kind, "name": self.name, "value": self.value,
            "status": self.status, "explanation": self.explanation, "note": self.note,
            "warning": self.warning, "replacement": self.replacement,
            "fix": self.fix.clone().map(Value::String).unwrap_or(Value::Null),
            "source": self.source,
            "flags": self.flags.iter().map(|f| json!({"flag": f.flag, "status": f.status, "note": f.note, "suggestion": f.suggestion})).collect::<Vec<_>>(),
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Problem {
    /// "command_missing", "command_twice", "duplicate".
    pub kind: &'static str,
    pub message: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct Report {
    pub ctx_json: Value,
    pub tokens: Vec<TokenCheck>,
    pub problems: Vec<Problem>,
    /// The text with every fix applied ("" when it cannot be fixed safely
    /// or nothing needs fixing).
    pub fixed: String,
    pub error: String,
}

impl Report {
    pub fn to_json(&self, text: &str) -> Value {
        let mut summary = serde_json::Map::new();
        for status in ["ok", "outdated", "invalid", "no_effect", "not_recommended", "unknown"] {
            summary.insert(status.into(), json!(self.tokens.iter().filter(|t| t.status == status && t.kind != "command").count()));
        }
        json!({
            "text": text,
            "proton": self.ctx_json,
            "tokens": self.tokens.iter().filter(|t| t.kind != "command" || t.status != "ok").map(TokenCheck::to_json).collect::<Vec<_>>(),
            "problems": self.problems.iter().map(|p| json!({"kind": p.kind, "message": p.message, "name": p.name})).collect::<Vec<_>>(),
            "summary": summary,
            "fixed": self.fixed,
            "error": self.error,
        })
    }

    #[cfg(test)]
    pub fn token(&self, name: &str) -> Option<&TokenCheck> {
        self.tokens.iter().find(|t| t.name == name)
    }
}

/// Levenshtein distance (small words only).
fn distance(a: &str, b: &str) -> usize {
    let b: Vec<char> = b.chars().collect();
    let mut row: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.chars().enumerate() {
        let mut prev = row[0];
        row[0] = i + 1;
        for (j, cb) in b.iter().enumerate() {
            let here = row[j + 1];
            row[j + 1] = (prev + usize::from(ca != *cb)).min(row[j] + 1).min(row[j + 1] + 1);
            prev = here;
        }
    }
    row[b.len()]
}

/// The nearest of `candidates` when it is surely a misspelling of `word`:
/// same letters in another case, or one or two letters off for words of
/// six letters or more (one for shorter ones).
fn nearest<'a>(word: &str, candidates: impl Iterator<Item = &'a str>) -> Option<&'a str> {
    let limit = if word.len() >= 6 { 2 } else { 1 };
    let mut best: Option<(usize, &str)> = None;
    for c in candidates {
        if c.contains('*') {
            continue;
        }
        let d = if c.eq_ignore_ascii_case(word) { 0 } else { distance(&word.to_ascii_lowercase(), &c.to_ascii_lowercase()) };
        if d <= limit && best.is_none_or(|(bd, _)| d < bd) {
            best = Some((d, c));
        }
    }
    best.map(|(_, c)| c)
}

fn flag_known(spec: &ValueSpec, flag: &str) -> bool {
    spec.values.iter().any(|v| match v.strip_suffix('*') {
        Some(prefix) => flag.starts_with(prefix) && flag.len() > prefix.len(),
        None => v == flag,
    })
}

/// Checks a value; Err((note, suggested value)).
fn check_value(entry: &Entry, value: &str, token: &mut TokenCheck) -> Result<(), (String, Option<String>)> {
    let spec = &entry.value;
    let name = &entry.name;
    match spec.kind.as_str() {
        "" | "any" => Ok(()),
        "bool" => {
            if value.is_empty() {
                Err((format!("{name} has no value; Proton options are turned on with 1 and off with 0."), Some("1".into())))
            } else {
                Ok(())
            }
        }
        "path" => {
            if value.is_empty() {
                Err((format!("{name} needs a folder or file."), None))
            } else {
                Ok(())
            }
        }
        "enum" => {
            if spec.values.iter().any(|v| v == value) {
                return Ok(());
            }
            let near = nearest(value, spec.values.iter().map(String::as_str)).map(str::to_string);
            Err((format!("{value:?} is not a value {name} knows ({}).", spec.values.join(", ")), near))
        }
        "number" => {
            let n: Option<f64> = value.trim().parse().ok();
            match n {
                Some(n) if spec.min.is_none_or(|m| n >= m) && spec.max.is_none_or(|m| n <= m) => Ok(()),
                Some(_) => Err((format!("{name} takes a number from {} to {}.", spec.min.unwrap_or(f64::MIN), spec.max.unwrap_or(f64::MAX)), None)),
                None => Err((format!("{name} takes a number."), None)),
            }
        }
        "version" => {
            let ok = !value.is_empty() && value.split('.').all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()));
            if ok {
                Ok(())
            } else {
                Err((format!("{name} takes 1 (the newest) or a version such as 4.0.1."), Some("1".into())))
            }
        }
        "size" => {
            let digits = value.trim_end_matches(['K', 'M', 'G', 'k', 'm', 'g']);
            if !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()) {
                Ok(())
            } else {
                Err((format!("{name} takes a size such as 10G."), None))
            }
        }
        "hidraw" => {
            let id = |s: &str| s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")).is_some_and(|h| !h.is_empty() && h.len() <= 4 && h.bytes().all(|b| b.is_ascii_hexdigit()));
            let list_ok = value.split(',').all(|p| p.split_once('/').is_some_and(|(v, d)| id(v) && id(d)));
            if value.chars().all(|c| c.is_ascii_digit()) && !value.is_empty() || list_ok {
                Ok(())
            } else {
                Err((format!("{name} takes 1, or vendor/product ids like 0x054C/0x0CE6 separated by commas."), None))
            }
        }
        "dll_overrides" => {
            for part in value.split(';').map(str::trim).filter(|p| !p.is_empty()) {
                let Some((dlls, mode)) = part.split_once('=') else {
                    return Err((format!("{part:?} lacks \"=mode\" (e.g. dxgi=n,b)."), None));
                };
                let mode_ok = matches!(mode.trim(), "" | "n" | "b" | "n,b" | "b,n" | "d");
                if dlls.trim().is_empty() || !mode_ok {
                    return Err((format!("{part:?}: the mode must be n, b, n,b, b,n or empty (off)."), None));
                }
            }
            Ok(())
        }
        "dxvk_config" => {
            for part in value.split(';').map(str::trim).filter(|p| !p.is_empty()) {
                let ok = part.split_once('=').is_some_and(|(k, _)| k.trim().contains('.'));
                if !ok {
                    return Err((format!("{part:?} is not a DXVK setting (section.option = value)."), None));
                }
            }
            Ok(())
        }
        "flags" => {
            let seps: Vec<char> = if spec.separator.is_empty() { vec![','] } else { spec.separator.chars().collect() };
            let mut fixed: Vec<String> = Vec::new();
            let mut any_fix = false;
            let mut worst = 0u8;
            for flag in value.split(|c| seps.contains(&c)).map(str::trim).filter(|f| !f.is_empty()) {
                let (status, note, suggestion) = if flag_known(spec, flag) {
                    ("ok", spec.notes.get(flag).cloned().unwrap_or_default(), String::new())
                } else if let Some(note) = spec.uncertain.get(flag) {
                    ("unknown", note.clone(), String::new())
                } else if let Some(near) = nearest(flag, spec.values.iter().map(String::as_str)) {
                    ("invalid", format!("Not a flag of {name}; did you mean {near}?"), near.to_string())
                } else {
                    ("unknown", format!("Not in this app's list of {name} flags; it may be newer or older than that list."), String::new())
                };
                worst = worst.max(match status {
                    "invalid" => 2,
                    "unknown" => 1,
                    _ => 0,
                });
                if suggestion.is_empty() {
                    fixed.push(flag.to_string());
                } else {
                    any_fix = true;
                    fixed.push(suggestion.clone());
                }
                token.flags.push(FlagCheck { flag: flag.into(), status, note, suggestion });
            }
            match worst {
                2 => Err(("A flag in the list is misspelt.".into(), any_fix.then(|| fixed.join(&seps[0].to_string())))),
                1 => {
                    if token.status == "ok" {
                        token.status = "unknown";
                    }
                    token.add_note("Some flags are not in this app's list.");
                    Ok(())
                }
                _ => Ok(()),
            }
        }
        _ => Ok(()),
    }
}

fn text_of(kind: &str, name: &str, value: &str) -> String {
    if kind == "env" {
        format!("{name}={}", if value.contains([' ', ';', '"', '\'', '$']) { format!("\"{value}\"") } else { value.to_string() })
    } else {
        name.to_string()
    }
}

/// Judges one known word in this context.
fn judge(entry: &Entry, token: &mut TokenCheck, ctx: &Ctx) {
    token.explanation = entry.explanation.clone();
    token.source = entry.source_text();
    token.warning = entry.warning.clone();
    let family = ctx.family;
    let over = entry.by_flavour.get(family.name()).filter(|o| match (o.from, family) {
        (Some(from), Family::Valve(m)) => m >= from,
        _ => true,
    });
    let flavours = entry.flavour_names();
    let works_here = flavours.contains(&family.name()) || (family == Family::ProtonOther && flavours.iter().any(|f| PROTONS.contains(f)));
    let (status, replacement, since, note) = match over {
        Some(o) => (o.status.as_str(), o.replacement.as_str(), o.since.as_str(), o.note.as_str()),
        None => (entry.status.as_str(), entry.replacement.as_str(), entry.since.as_str(), ""),
    };
    if over.is_none() && !works_here {
        token.status = "no_effect";
        let what = match family {
            Family::Native => "This game runs natively, not through Proton or Wine".to_string(),
            Family::Wine => "This game runs through Wine, not Proton".to_string(),
            _ => format!("This game uses {}", if ctx.tool.is_empty() { flavour_label(family.name()).to_string() } else { ctx.tool.clone() }),
        };
        token.add_note(&format!("{what}; {} only works with {}.", entry.name, list_label(&flavours)));
        token.add_note(&entry.note);
        token.fix = Some(String::new());
        return;
    }
    if family == Family::ProtonOther && !PROTONS.iter().all(|p| flavours.contains(p)) {
        token.add_note(&format!("Which Proton this game uses is not known; {} only works with {}.", entry.name, list_label(&flavours)));
    }
    if !ctx.sure && family.proton() && entry.flavours.iter().all(|f| f != "all") {
        token.add_note("Only if the game runs through Proton.");
    }
    if !entry.vendor.is_empty() && !ctx.gpus.is_empty() && !ctx.has_gpu(&entry.vendor) {
        token.status = "no_effect";
        token.add_note(&format!("Only for {} graphics, and this computer has none.", vendor_label(&entry.vendor)));
        token.fix = Some(String::new());
        return;
    }
    if entry.container && ctx.outside_container() {
        token.status = "no_effect";
        token.add_note("This proton-cachyos build runs without Steam's runtime container, so container settings do nothing.");
        token.fix = Some(String::new());
        return;
    }
    match status {
        "retired" => {
            token.status = "outdated";
            token.replacement = replacement.to_string();
            let mut text = if since.is_empty() { "Retired.".to_string() } else { format!("Retired ({since}).") };
            if !replacement.is_empty() {
                text.push_str(&format!(" Use {replacement} instead."));
            }
            token.add_note(&text);
            token.add_note(note);
            if over.is_none() {
                token.add_note(&entry.note);
            }
            token.fix = Some(replacement.to_string());
            return;
        }
        "discouraged" => token.status = "not_recommended",
        "unverified" => {
            token.status = "unknown";
            token.add_note("No source read for this app confirms what it does.");
        }
        "debug" => token.add_note("For troubleshooting: take it out when done."),
        _ => {}
    }
    token.add_note(note);
    if over.is_none() && status != "retired" {
        token.add_note(&entry.note);
    }
    // Wrappers: installed, and what they clash with.
    if entry.kind == "wrapper" {
        if !entry.tool.is_empty() && crate::system_info::TOOLS.contains(&entry.tool.as_str()) && !ctx.has_tool(&entry.tool) && !ctx.tools.is_empty() {
            token.status = "invalid";
            token.add_note(&format!("{} is not installed (not found on PATH): the game will not start this way.", entry.tool));
            token.fix = Some(String::new());
            return;
        }
        if entry.name == "gamemoderun" && ctx.ananicy {
            token.status = "not_recommended";
            token.warning = "GameMode and ananicy-cpp (running here) both change process priorities and get in each other's way (CachyOS wiki). Stop ananicy-cpp first, or use game-performance.".into();
        } else if entry.name == "gamemoderun" && ctx.cachyos && ctx.has_tool("game-performance") {
            token.add_note("On CachyOS, game-performance is the suggested alternative.");
        }
        if entry.name == "game-performance" && !ctx.has_tool("powerprofilesctl") && !ctx.tools.is_empty() {
            token.status = "not_recommended";
            token.warning = "game-performance needs power-profiles-daemon, which is not installed (powerprofilesctl not found).".into();
        }
    }
    if entry.name == "ENABLE_HDR_WSI" && ctx.family == Family::CachyOs && ctx.nvidia_major.is_some_and(|m| m >= 595) && !ctx.has_gpu("amd") {
        token.add_note("proton-cachyos's README calls for it only on NVIDIA drivers older than 595; this one is newer.");
    }
    if entry.kind == "env" {
        let value = token.value.clone();
        if let Err((note, suggestion)) = check_value(entry, &value, token) {
            token.status = "invalid";
            token.add_note(&note);
            token.fix = suggestion.map(|v| text_of("env", &token.name, &v));
        }
    }
}

fn vendor_label(v: &str) -> &'static str {
    match v {
        "nvidia" => "NVIDIA",
        "amd" => "AMD",
        "intel" => "Intel",
        _ => "other",
    }
}

/// Checks a word whose kind and name are known (env var, wrapper, arg).
pub fn check_word(kind: &'static str, name: &str, value: &str, text: &str, span: (usize, usize), ctx: &Ctx) -> TokenCheck {
    let mut token = TokenCheck::new(text, kind, name, value, span);
    if let Some(entry) = find(kind, name) {
        judge(entry, &mut token, ctx);
        return token;
    }
    match kind {
        "env" => {
            let names = kb().entries.iter().filter(|e| e.kind == "env" && !e.prefix).flat_map(|e| e.names());
            if let Some(near) = nearest(name, names) {
                token.status = "invalid";
                token.add_note(&format!("Not a known setting; did you mean {near}?"));
                token.fix = Some(text_of("env", near, value));
                if let Some(e) = find("env", near) {
                    token.explanation = format!("({near}) {}", e.explanation);
                    token.source = e.source_text();
                }
            } else if name.starts_with("PROTON_") && !ctx.family.proton() {
                token.status = "no_effect";
                token.explanation = "A Proton setting.".into();
                token.add_note("PROTON_ settings only do something for games that run through Proton.");
                token.fix = Some(String::new());
            } else {
                token.status = "unknown";
                token.explanation = "Not in this app's list of known settings: it may be fine, but nothing here can tell what it does.".into();
            }
        }
        "wrapper" => {
            token.status = "unknown";
            token.explanation = "A program the game is started through. It is not in this app's list, so nothing here can tell what it does.".into();
        }
        _ => {
            token.status = "unknown";
            token.explanation = "Passed to the game itself; what it does depends on the game.".into();
        }
    }
    token
}

/// Checks launch options (Steam's form, or an own entry's command line)
/// word by word, plus `%command%` and settings given twice.
pub fn check(text: &str, ctx: &Ctx) -> Report {
    let mut report = Report { ctx_json: ctx.to_json(), tokens: Vec::new(), problems: Vec::new(), fixed: String::new(), error: String::new() };
    let toks = match launch_options::lex_words(text) {
        Ok(t) => t,
        Err(e) => {
            report.error = e;
            return report;
        }
    };
    let has_ops = toks.iter().any(|t| t.2);
    let words: Vec<(String, (usize, usize))> = toks.iter().filter(|t| !t.2).map(|t| (t.0.clone(), (t.1 .0, t.1 .1))).collect();
    let raw = |span: (usize, usize)| text[span.0..span.1].to_string();
    let commands: Vec<usize> = words.iter().enumerate().filter(|(_, (w, _))| w.contains("%command%")).map(|(i, _)| i).collect();
    let first_cmd = commands.first().copied();
    // Settings, wrappers and the game's command.
    let (before, after_from) = if ctx.steam_form {
        match first_cmd {
            Some(c) => (c, c + 1),
            None => {
                // Without %command% Steam puts everything after the game.
                let looks_like_options = words.iter().take_while(|(w, _)| launch_options::is_assignment(w) || find("wrapper", launch_options::program_name(w)).is_some()).count();
                if looks_like_options > 0 {
                    report.problems.push(Problem {
                        kind: "command_missing",
                        message: "%command% is missing: Steam passes all of this to the game as arguments, so the settings and programs do nothing. Put %command% after them.".into(),
                        name: String::new(),
                    });
                    (looks_like_options, looks_like_options)
                } else {
                    (0, 0)
                }
            }
        }
    } else {
        (words.len(), words.len())
    };
    if commands.len() > 1 {
        report.problems.push(Problem {
            kind: "command_twice",
            message: "%command% appears more than once; use it only once (anything after a second one counts as the game's arguments).".into(),
            name: String::new(),
        });
    }
    let mut i = 0;
    while i < before && launch_options::is_assignment(&words[i].0) {
        let (name, value) = words[i].0.split_once('=').unwrap_or((&words[i].0, ""));
        report.tokens.push(check_word("env", name, value, &raw(words[i].1), words[i].1, ctx));
        i += 1;
    }
    let mut own_program = false;
    while i < before {
        let (w, span) = &words[i];
        let program = launch_options::program_name(w);
        if find("wrapper", program).is_some() || launch_options::is_wrapper(program) {
            let mut token = check_word("wrapper", program, "", &raw(*span), *span, ctx);
            i += 1;
            // The wrapper's own words: gamescope's up to "--"; env's settings.
            let gamescope = program == "gamescope";
            while i < before {
                let next = &words[i].0;
                let next_program = launch_options::program_name(next);
                if gamescope {
                    token.span.1 = words[i].1 .1;
                    i += 1;
                    if next == "--" {
                        break;
                    }
                    continue;
                }
                if find("wrapper", next_program).is_some() || launch_options::is_wrapper(next_program) {
                    break;
                }
                if program == "env" && launch_options::is_assignment(next) {
                    let (name, value) = next.split_once('=').unwrap_or((next, ""));
                    report.tokens.push(check_word("env", name, value, &raw(words[i].1), words[i].1, ctx));
                } else if !ctx.steam_form {
                    // An own entry's wrappers take no words: the next one
                    // is the program.
                    break;
                } else {
                    token.span.1 = words[i].1 .1;
                }
                i += 1;
            }
            token.text = raw(token.span);
            report.tokens.push(token);
        } else if !ctx.steam_form {
            // An own entry's program and its words.
            let span = (span.0, words[before - 1].1 .1);
            let mut token = TokenCheck::new(&raw(span), "command", program, "", span);
            token.explanation = "The game's own command.".into();
            report.tokens.push(token);
            own_program = true;
            break;
        } else {
            report.tokens.push(check_word("wrapper", program, "", &raw(*span), *span, ctx));
            i += 1;
        }
    }
    if !ctx.steam_form && !own_program {
        report.problems.push(Problem { kind: "command_missing", message: "The command is missing.".into(), name: String::new() });
    }
    for (w, span) in words.iter().skip(after_from) {
        if w.contains("%command%") {
            let mut token = TokenCheck::new(&raw(*span), "command", "%command%", "", *span);
            token.explanation = "Where Steam puts the game.".into();
            if Some(words.iter().position(|(_, s)| s == span).unwrap_or(0)) != first_cmd {
                token.status = "invalid";
                token.add_note("A second %command%.");
            }
            report.tokens.push(token);
            continue;
        }
        let name = w.split_once('=').map(|(n, _)| n).unwrap_or(w);
        report.tokens.push(check_word("arg", name, "", &raw(*span), *span, ctx));
    }
    // Settings given twice (aliases count as one): the last one wins.
    let key = |t: &TokenCheck| -> String { find(t.kind, &t.name).map(|e| e.name.clone()).unwrap_or_else(|| t.name.clone()) };
    let n = report.tokens.len();
    for a in 0..n {
        let t = &report.tokens[a];
        if !matches!(t.kind, "env" | "wrapper") {
            continue;
        }
        let k = key(t);
        let later = report.tokens[a + 1..].iter().any(|u| u.kind == t.kind && key(u) == k);
        if later {
            let t = &mut report.tokens[a];
            t.status = "no_effect";
            t.add_note(if t.kind == "env" { "Set again later in the text: the later one wins." } else { "Given twice." });
            t.fix = Some(String::new());
            if !report.problems.iter().any(|p| p.kind == "duplicate" && p.name == k) {
                report.problems.push(Problem { kind: "duplicate", message: format!("{k} is given more than once."), name: k });
            }
        }
    }
    report.fixed = if has_ops { String::new() } else { apply_fixes(text, &report) };
    report
}

/// The text with every token's fix in place (and a missing `%command%`).
fn apply_fixes(text: &str, report: &Report) -> String {
    let mut edits: Vec<(usize, usize, String)> = report.tokens.iter().filter_map(|t| t.fix.clone().map(|f| (t.span.0, t.span.1, f))).collect();
    let missing = report.problems.iter().any(|p| p.kind == "command_missing");
    if edits.is_empty() && !missing {
        return String::new();
    }
    if missing {
        // After the last setting or program.
        let at = report.tokens.iter().filter(|t| matches!(t.kind, "env" | "wrapper")).map(|t| t.span.1).max().unwrap_or(0);
        edits.push((at, at, " %command%".into()));
    }
    edits.sort_by_key(|e| std::cmp::Reverse(e.0));
    let mut out = text.to_string();
    for (start, end, new) in edits {
        let (mut s, mut e) = (start, end);
        if new.is_empty() {
            // Take one space with the word.
            if out[e..].starts_with(' ') {
                e += 1;
            } else if s > 0 && out[..s].ends_with(' ') {
                s -= 1;
            }
        }
        out.replace_range(s..e, &new);
    }
    let out = out.trim().to_string();
    if out == text.trim() {
        String::new()
    } else {
        out
    }
}

/// The answer of `Games.suggestions`: `{"suggestions":[..],"context":
/// {"flavour","label","sure","cachyos"},"check":<check's answer for the
/// current text>,"warnings":[".."],"others":<protondb::others>|null}`.
/// With ProtonDB's entry for the game, suggestions others use (on systems
/// like this one) move up among their equals; `recommended` stays as it is.
pub fn suggestions_answer(sys: &SystemInfo, current: &Current, tools: &[Tool], pdb: Option<(crate::protondb::Meta, crate::protondb::Game)>) -> Value {
    let mut list = launch_options::suggest(sys, current, tools);
    let ctx = context(sys, current, tools);
    let prime = current.spec.wrappers.iter().any(|w| launch_options::program_name(&w[0]) == "prime-run");
    let groups = crate::protondb::groups_of(&sys.gpu_in_use(prime), sys.distro_group(), &sys.cpu_vendor);
    let others = pdb.map(|(meta, game)| {
        for s in &mut list {
            s.popular = crate::protondb::popularity(&game, &groups, &s.option);
            s.share = s.popular.as_ref().and_then(|p| p["like"]["share"].as_f64()).unwrap_or(0.0);
        }
        list.sort_by(|a, b| b.recommended.cmp(&a.recommended).then(b.share.total_cmp(&a.share)));
        crate::protondb::others(&meta, &game, &groups, &ctx)
    });
    let report = check(&current.text, &ctx);
    let mut warnings: Vec<String> = Vec::new();
    let uses = |p: &str| report.tokens.iter().any(|t| t.kind == "wrapper" && t.name == p);
    if sys.ananicy && uses("gamemoderun") {
        warnings.push("ananicy-cpp is running and this game starts through GameMode: both change process priorities and get in each other's way (CachyOS wiki).".into());
    }
    if !ctx.sure && ctx.family.proton() {
        warnings.push("This game has no Proton chosen and Steam has made no Proton prefix for it yet: it may be a native Linux game, so Proton options are shown but not recommended.".into());
    }
    json!({
        "suggestions": launch_options::suggestions_json(&list),
        "context": ctx.to_json(),
        "check": report.to_json(&current.text),
        "warnings": warnings,
        "others": others.unwrap_or(Value::Null),
    })
}

/// Explanation and flavours of a suggestion's option (`NAME=value ...
/// wrapper %command%`): the flavours all its parts work with.
pub fn option_info(option: &str) -> (Vec<&'static str>, Vec<String>) {
    let mut flavours: Vec<&'static str> = ALL.to_vec();
    let mut sources: Vec<String> = Vec::new();
    for word in option.split_whitespace() {
        let entry = if let Some((name, _)) = word.split_once('=').filter(|_| launch_options::is_assignment(word)) {
            find("env", name)
        } else {
            find("wrapper", launch_options::program_name(word))
        };
        if let Some(e) = entry {
            let f = e.flavour_names();
            flavours.retain(|x| f.contains(x));
            for s in e.source.split(',').map(str::trim) {
                if !s.is_empty() && !sources.iter().any(|x| x == s) {
                    sources.push(s.to_string());
                }
            }
        }
    }
    (flavours, sources)
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn ctx(family: Family) -> Ctx {
        Ctx {
            family,
            tool: match family {
                Family::CachyOs => "proton-cachyos-slr".into(),
                Family::Ge(..) => "GE-Proton10-25".into(),
                Family::Experimental => "Proton - Experimental".into(),
                Family::Valve(_) => "Proton 11.0".into(),
                _ => String::new(),
            },
            sure: true,
            gpus: vec!["nvidia".into()],
            nvidia_major: Some(595),
            tools: vec!["gamemoderun".into(), "game-performance".into(), "powerprofilesctl".into(), "mangohud".into()],
            ananicy: false,
            cachyos: true,
            steam_form: true,
        }
    }

    fn statuses(r: &Report) -> Vec<(&str, &str)> {
        r.tokens.iter().filter(|t| t.kind != "command").map(|t| (t.name.as_str(), t.status)).collect()
    }

    #[test]
    fn knowledge_base_is_complete() {
        let kb = kb();
        assert!(kb.entries.len() > 150);
        for e in &kb.entries {
            assert!(!e.explanation.is_empty(), "{} has no explanation", e.name);
            assert!(!e.flavour_names().is_empty(), "{} works nowhere", e.name);
            assert!(matches!(e.kind.as_str(), "env" | "wrapper" | "arg"), "{}", e.name);
            assert!(matches!(e.status.as_str(), "current" | "retired" | "discouraged" | "experimental" | "debug" | "unverified"), "{}", e.name);
            for s in e.source.split(',').map(str::trim) {
                assert!(kb.sources.contains_key(s), "{}: source {s}", e.name);
            }
            for o in e.by_flavour.values() {
                assert!(matches!(o.status.as_str(), "current" | "retired" | "discouraged"), "{}", e.name);
            }
            // Names are unique.
            assert_eq!(kb.entries.iter().filter(|x| x.kind == e.kind && x.names().any(|n| e.names().any(|m| m == n))).count(), 1, "{}", e.name);
        }
    }

    /// The person's Forza Horizon 6 options.
    const FORZA: &str = "PROTON_DISABLE_HIDRAW=1 VKD3D_CONFIG=descriptor_heap,enable_experimental_features PROTON_VKD3D_HEAP=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%";

    #[test]
    fn checks_the_forza_options() {
        // proton-cachyos: PROTON_VKD3D_HEAP is retired (no replacement).
        let r = check(FORZA, &ctx(Family::CachyOs));
        assert_eq!(
            statuses(&r),
            [("PROTON_DISABLE_HIDRAW", "ok"), ("VKD3D_CONFIG", "ok"), ("PROTON_VKD3D_HEAP", "outdated"), ("PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES", "ok")]
        );
        let vkd3d = r.token("VKD3D_CONFIG").unwrap();
        let flags: Vec<(&str, &str)> = vkd3d.flags.iter().map(|f| (f.flag.as_str(), f.status)).collect();
        assert_eq!(flags, [("descriptor_heap", "ok"), ("enable_experimental_features", "ok")]);
        assert!(vkd3d.flags[0].note.contains("2026-11-04") && vkd3d.flags[1].note.contains("Not in vkd3d-proton's README"));
        let heap = r.token("PROTON_VKD3D_HEAP").unwrap();
        assert!(heap.note.contains("11.0-20260521") && heap.note.contains("VKD3D_CONFIG=descriptor_heap"));
        assert_eq!(heap.fix.as_deref(), Some(""));
        assert!(r.token("PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES").unwrap().explanation.contains("VR"));
        assert!(r.tokens.iter().all(|t| !t.explanation.is_empty()));
        assert!(r.problems.is_empty());
        assert_eq!(r.fixed, "PROTON_DISABLE_HIDRAW=1 VKD3D_CONFIG=descriptor_heap,enable_experimental_features PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%");
        // Valve's Proton and GE-Proton never read PROTON_VKD3D_HEAP.
        for family in [Family::Valve(11), Family::Experimental, Family::Ge(10, 25)] {
            let r = check(FORZA, &ctx(family));
            let heap = r.token("PROTON_VKD3D_HEAP").unwrap();
            assert_eq!(heap.status, "no_effect", "{family:?}");
            assert!(heap.note.contains("only works with proton-cachyos"));
            assert_eq!(r.token("VKD3D_CONFIG").unwrap().status, "ok");
        }
        // A proton-cachyos build without Steam's container.
        let mut native = ctx(Family::CachyOs);
        native.tool = "proton-cachyos-native".into();
        assert_eq!(check(FORZA, &native).token("PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES").unwrap().status, "no_effect");
        let json = check(FORZA, &ctx(Family::CachyOs)).to_json(FORZA);
        assert_eq!(json["summary"]["outdated"], 1);
        assert_eq!(json["tokens"][1]["flags"][0]["flag"], "descriptor_heap");
    }

    #[test]
    fn statuses_follow_the_flavour() {
        let hdr = "PROTON_ENABLE_HDR=1 %command%";
        let t = |text: &str, f: Family, name: &str| -> TokenCheck { check(text, &ctx(f)).token(name).cloned().unwrap() };
        let c = t(hdr, Family::CachyOs, "PROTON_ENABLE_HDR");
        assert_eq!((c.status, c.replacement.as_str(), c.fix.as_deref()), ("outdated", "DXVK_HDR=1", Some("DXVK_HDR=1")));
        assert_eq!(t(hdr, Family::Ge(10, 25), "PROTON_ENABLE_HDR").status, "outdated");
        assert_eq!(t(hdr, Family::Valve(11), "PROTON_ENABLE_HDR").status, "no_effect");
        // NTSync is on by default; the old switch is retired.
        assert_eq!(t("PROTON_USE_NTSYNC=1 %command%", Family::CachyOs, "PROTON_USE_NTSYNC").status, "outdated");
        assert_eq!(t("PROTON_USE_NTSYNC=1 %command%", Family::Valve(11), "PROTON_USE_NTSYNC").status, "no_effect");
        // Retired from Proton 11 on, fine before.
        assert_eq!(t("PROTON_NO_ESYNC=1 %command%", Family::Valve(11), "PROTON_NO_ESYNC").status, "outdated");
        assert_eq!(t("PROTON_NO_ESYNC=1 %command%", Family::Valve(9), "PROTON_NO_ESYNC").status, "ok");
        assert_eq!(t("PROTON_NO_ESYNC=1 %command%", Family::Ge(10, 25), "PROTON_NO_ESYNC").status, "ok");
        // proton-cachyos's own options do nothing elsewhere.
        assert_eq!(t("PROTON_DXVK_SAREK=1 %command%", Family::Valve(11), "PROTON_DXVK_SAREK").status, "no_effect");
        let sarek = t("PROTON_DXVK_SAREK=1 %command%", Family::CachyOs, "PROTON_DXVK_SAREK");
        assert_eq!(sarek.status, "not_recommended");
        assert!(sarek.warning.contains("anti-cheat"));
        assert_eq!(t("PROTON_ENABLE_MEDIACONV=1 %command%", Family::CachyOs, "PROTON_ENABLE_MEDIACONV").status, "not_recommended");
        assert_eq!(t("PROTON_ENABLE_MEDIACONV=1 %command%", Family::Ge(10, 25), "PROTON_ENABLE_MEDIACONV").status, "ok");
        // Wayland: warned, and not in Valve's builds.
        let w = t("PROTON_ENABLE_WAYLAND=1 %command%", Family::CachyOs, "PROTON_ENABLE_WAYLAND");
        assert!(w.status == "ok" && w.warning.contains("experimental"));
        assert_eq!(t("PROTON_USE_WAYLAND=1 %command%", Family::Experimental, "PROTON_USE_WAYLAND").status, "no_effect");
        // Any Proton setting for a native game.
        assert_eq!(t("PROTON_LOG=1 %command%", Family::Native, "PROTON_LOG").status, "no_effect");
        assert_eq!(t("PROTON_WHATEVER_NEW=1 %command%", Family::Native, "PROTON_WHATEVER_NEW").status, "no_effect");
        assert_eq!(t("PROTON_WHATEVER_NEW=1 %command%", Family::CachyOs, "PROTON_WHATEVER_NEW").status, "unknown");
        // Renamed, with the replacement as the fix.
        let r = check("PROTON_MEDIA_USE_GST=1 PROTON_VKREFLEX=1 %command%", &ctx(Family::CachyOs));
        assert_eq!(r.fixed, "PROTON_MEDIA_FORCE_GST=1 DXVK_NVAPI_VKREFLEX=1 %command%");
        // NVIDIA-only on an AMD computer.
        let mut amd = ctx(Family::CachyOs);
        amd.gpus = vec!["amd".into()];
        assert_eq!(check("PROTON_DLSS_UPGRADE=1 %command%", &amd).token("PROTON_DLSS_UPGRADE").unwrap().status, "no_effect");
        assert_eq!(check("PROTON_FSR4_UPGRADE=1 %command%", &amd).token("PROTON_FSR4_UPGRADE").unwrap().status, "ok");
        // DXVK_ASYNC is no upstream DXVK option; NVAPI is on by default.
        assert_eq!(t("DXVK_ASYNC=1 %command%", Family::Valve(11), "DXVK_ASYNC").status, "outdated");
        assert_eq!(t("PROTON_ENABLE_NVAPI=1 %command%", Family::Ge(10, 25), "PROTON_ENABLE_NVAPI").status, "outdated");
    }

    #[test]
    fn finds_misspellings_and_bad_values() {
        let mut c = ctx(Family::CachyOs);
        c.gpus.push("amd".into());
        let r = check("PROTON_ENABLE_WAYLNAD=1 VKD3D_CONFIG=dxr,single_queu,brand_new_flag DXVK_HUD=fps,memroy %command%", &c);
        let way = r.token("PROTON_ENABLE_WAYLNAD").unwrap();
        assert_eq!((way.status, way.fix.as_deref()), ("invalid", Some("PROTON_ENABLE_WAYLAND=1")));
        let vk = r.token("VKD3D_CONFIG").unwrap();
        assert_eq!(vk.status, "invalid");
        let flags: Vec<(&str, &str, &str)> = vk.flags.iter().map(|f| (f.flag.as_str(), f.status, f.suggestion.as_str())).collect();
        assert_eq!(flags, [("dxr", "ok", ""), ("single_queu", "invalid", "single_queue"), ("brand_new_flag", "unknown", "")]);
        assert_eq!(vk.fix.as_deref(), Some("VKD3D_CONFIG=dxr,single_queue,brand_new_flag"));
        assert_eq!(r.token("DXVK_HUD").unwrap().fix.as_deref(), Some("DXVK_HUD=fps,memory"));
        // Lower case names.
        assert_eq!(check("proton_log=1 %command%", &c).token("proton_log").unwrap().fix.as_deref(), Some("PROTON_LOG=1"));
        // Values.
        let bad = |text: &str, name: &str| check(text, &c).token(name).unwrap().status;
        assert_eq!(bad("VKD3D_SWAPCHAIN_PRESENT_MODE=MAILBX %command%", "VKD3D_SWAPCHAIN_PRESENT_MODE"), "invalid");
        assert_eq!(bad("WINEDLLOVERRIDES=\"winmm=n,b;steam_api64=n,b\" %command%", "WINEDLLOVERRIDES"), "ok");
        assert_eq!(bad("WINEDLLOVERRIDES=dxgi %command%", "WINEDLLOVERRIDES"), "invalid");
        assert_eq!(bad("WINEDLLOVERRIDES=dxgi=x %command%", "WINEDLLOVERRIDES"), "invalid");
        assert_eq!(bad("PROTON_FSR4_UPGRADE=4.0.1 %command%", "PROTON_FSR4_UPGRADE"), "ok");
        assert_eq!(bad("PROTON_FSR4_UPGRADE=yes %command%", "PROTON_FSR4_UPGRADE"), "invalid");
        assert_eq!(bad("PROTON_DISABLE_HIDRAW=0x054C/0x0CE6,0x054C/0x05C4 %command%", "PROTON_DISABLE_HIDRAW"), "ok");
        assert_eq!(bad("PROTON_DISABLE_HIDRAW=sony %command%", "PROTON_DISABLE_HIDRAW"), "invalid");
        assert_eq!(bad("DXVK_CONFIG=\"dxgi.maxFrameRate = 60; d3d9.maxFrameRate = 60\" %command%", "DXVK_CONFIG"), "ok");
        assert_eq!(bad("WINE_FULLSCREEN_FSR_STRENGTH=9 %command%", "WINE_FULLSCREEN_FSR_STRENGTH"), "invalid");
        assert_eq!(bad("DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE=on %command%", "DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE"), "ok");
        assert_eq!(bad("SOME_THING_ELSE=1 %command%", "SOME_THING_ELSE"), "unknown");
        assert_eq!(bad("PROTON_ENABLE_HIDRAW=1 %command%", "PROTON_ENABLE_HIDRAW"), "unknown");
    }

    #[test]
    fn answers_suggestions_with_what_others_use() {
        use crate::system_info::{Gpu, SystemInfo};
        let path = crate::protondb::tests::fixture("answer");
        let pdb = crate::protondb::load(&path, "2483190");
        let sys = SystemInfo {
            gpus: vec![Gpu { vendor: "amd".into(), driver: "amdgpu".into(), card: "card0".into() }],
            tools: vec![("gamemoderun".into(), "/usr/bin/gamemoderun".into())],
            session: "wayland".into(),
            ntsync: true,
            os_id: "cachyos".into(),
            cpu_vendor: "amd".into(),
            ..Default::default()
        };
        let current = Current {
            launcher: "steam".into(),
            supported: true,
            text: FORZA.into(),
            spec: launch_options::parse(FORZA).unwrap(),
            tool: "proton-cachyos-slr".into(),
            proton: Some(true),
            ..Default::default()
        };
        let a = suggestions_answer(&sys, &current, &[], pdb);
        assert_eq!(a["context"]["flavour"], "cachyos");
        assert_eq!(a["check"]["summary"]["outdated"], 1);
        assert_eq!(a["others"]["groups"][0]["group"], "gpu:amd");
        let list = a["suggestions"].as_array().unwrap();
        // Recommended first; then what AMD users of this game use most
        // (native Wayland, 48 of 282) moves up, still not recommended.
        let ids: Vec<&str> = list.iter().map(|s| s["id"].as_str().unwrap()).collect();
        assert_eq!(&ids[..3], ["gamemode", "wayland", "no_ntsync"]);
        assert_eq!(list[1]["recommended"], false);
        assert_eq!(list[1]["popular"]["like"]["count"], 48);
        assert!(list.iter().all(|s| !s["explanation"].as_str().unwrap().is_empty()));
        // Without ProtonDB's entry: no "others".
        assert!(suggestions_answer(&sys, &current, &[], None)["others"].is_null());
    }

    #[test]
    fn checks_wrappers_command_and_doubles() {
        let mut c = ctx(Family::CachyOs);
        // %command% missing: everything would be an argument.
        let r = check("PROTON_LOG=1 gamemoderun", &c);
        assert_eq!(r.problems[0].kind, "command_missing");
        assert_eq!(r.fixed, "PROTON_LOG=1 gamemoderun %command%");
        // Twice.
        let r = check("%command% ; %command%", &c);
        assert!(r.problems.iter().any(|p| p.kind == "command_twice"));
        // The later setting wins; aliases count as one.
        let r = check("PROTON_USE_WAYLAND=1 PROTON_ENABLE_WAYLAND=0 %command%", &c);
        assert_eq!(statuses(&r), [("PROTON_USE_WAYLAND", "no_effect"), ("PROTON_ENABLE_WAYLAND", "ok")]);
        assert_eq!(r.problems[0].name, "PROTON_ENABLE_WAYLAND");
        assert_eq!(r.fixed, "PROTON_ENABLE_WAYLAND=0 %command%");
        // Wrappers: not installed, clashing with ananicy-cpp, needing ppd.
        let r = check("prime-run gamescope -W 2560 -H 1440 -- gamemoderun %command% -dx12", &c);
        assert_eq!(statuses(&r), [("prime-run", "invalid"), ("gamescope", "invalid"), ("gamemoderun", "ok"), ("-dx12", "unknown")]);
        assert_eq!(r.tokens[1].text, "gamescope -W 2560 -H 1440 --");
        assert!(r.token("gamemoderun").unwrap().note.contains("game-performance"));
        c.ananicy = true;
        let g = check("gamemoderun %command%", &c).token("gamemoderun").cloned().unwrap();
        assert_eq!(g.status, "not_recommended");
        assert!(g.warning.contains("ananicy-cpp"));
        c.tools.retain(|t| t != "powerprofilesctl");
        assert_eq!(check("game-performance %command%", &c).token("game-performance").unwrap().status, "not_recommended");
        assert_eq!(check("unheard-of-wrapper %command%", &c).token("unheard-of-wrapper").unwrap().status, "unknown");
        // An own entry: settings, then the program.
        let mut own = ctx(Family::Wine);
        own.steam_form = false;
        let r = check("WINEPREFIX=$HOME/p DXVK_HUD=fps mangohud wine ~/a.exe", &own);
        assert_eq!(statuses(&r), [("WINEPREFIX", "ok"), ("DXVK_HUD", "ok"), ("mangohud", "ok")]);
        assert!(r.problems.is_empty());
        assert!(check("\"open %command%", &c).error.contains("quote"));
    }
}
