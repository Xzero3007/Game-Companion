//! "What others use": launch options and Proton builds from ProtonDB's
//! reports of a Steam game, from the extract shipped with the app
//! (`data/protondb.json.gz`, made by `tools/protondb-extract.py` from
//! ProtonDB's data export, ODbL 1.0; see NOTICE-ProtonDB.txt). Read from
//! disk on the worker thread when asked, only the one game kept; nothing
//! is fetched.
//!
//! Counts are working reports ("verdict yes") of the last months, also per
//! group of systems ("gpu:nvidia", "os:cachyos", "cpu:amd", ...), so an
//! option used on NVIDIA cards does not look like everyone's choice on an
//! AMD one.

use std::collections::{BTreeMap, HashMap};
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde_json::value::RawValue;
use serde_json::{json, Value};

use crate::launch_check::{self, Ctx};

/// Groups with fewer reports than this fall back to the next group (or to
/// all reports).
pub const MIN_GROUP: u32 = 5;

/// Options shown at most.
const SHOWN: usize = 10;

#[derive(Debug, Clone, Deserialize)]
pub struct Game {
    #[serde(default)]
    pub title: String,
    pub reports: u32,
    #[serde(default)]
    pub groups: BTreeMap<String, u32>,
    #[serde(default)]
    pub proton: Vec<Variant>,
    #[serde(default)]
    pub options: Vec<Opt>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Variant {
    pub variant: String,
    pub count: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Opt {
    /// "env", "wrapper" or "arg".
    pub kind: String,
    pub name: String,
    #[serde(default)]
    pub value: Option<String>,
    pub count: u32,
    #[serde(default)]
    pub by: BTreeMap<String, u32>,
}

#[derive(Debug, Clone, Default)]
pub struct Meta {
    pub source: String,
    pub export: String,
    pub months: u32,
}

#[derive(Deserialize)]
struct Raw<'a> {
    #[serde(default)]
    source: String,
    #[serde(default)]
    export: String,
    #[serde(default)]
    months: u32,
    #[serde(borrow)]
    games: HashMap<&'a str, &'a RawValue>,
}

/// Where the extract is: `GC_PROTONDB`, the package's
/// /usr/share/game-companion, else the repository's data folder.
pub fn data_path() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("GC_PROTONDB").map(PathBuf::from) {
        return p.is_file().then_some(p);
    }
    [PathBuf::from("/usr/share/game-companion/protondb.json.gz"), PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/data/protondb.json.gz"))]
        .into_iter()
        .find(|p| p.is_file())
}

/// One game's entry (by Steam app id) from the extract (gzip or plain JSON).
pub fn load(path: &Path, appid: &str) -> Option<(Meta, Game)> {
    let file = std::fs::File::open(path).ok()?;
    let mut text = String::new();
    if path.extension().is_some_and(|e| e == "gz") {
        flate2::read::GzDecoder::new(file).take(64 << 20).read_to_string(&mut text).ok()?;
    } else {
        file.take(64 << 20).read_to_string(&mut text).ok()?;
    }
    let raw: Raw = serde_json::from_str(&text).ok()?;
    let game: Game = serde_json::from_str(raw.games.get(appid)?.get()).ok()?;
    Some((Meta { source: raw.source, export: raw.export, months: raw.months }, game))
}

/// This computer's groups, most telling first: graphics in use, then the
/// distribution's family, then the processor ("gpu:amd", "os:cachyos",
/// "cpu:amd"); unknown ones left out.
pub fn groups_of(gpu: &str, distro: &str, cpu: &str) -> Vec<String> {
    let mut out = Vec::new();
    if !gpu.is_empty() {
        out.push(format!("gpu:{gpu}"));
    }
    if !distro.is_empty() {
        out.push(format!("os:{distro}"));
    }
    if !cpu.is_empty() {
        out.push(format!("cpu:{cpu}"));
    }
    out
}

fn group_label(group: &str) -> String {
    let (kind, name) = group.split_once(':').unwrap_or(("", group));
    let name = match name {
        "nvidia" => "NVIDIA",
        "amd" => "AMD",
        "intel" => "Intel",
        "deck" => "Steam Deck",
        "cachyos" => "CachyOS",
        "arch" => "Arch-based",
        "steamos" => "SteamOS",
        "bazzite" => "Bazzite",
        "fedora" => "Fedora-based",
        "debian" => "Debian/Ubuntu-based",
        "nixos" => "NixOS",
        "suse" => "openSUSE",
        "gentoo" => "Gentoo",
        "other" => "other",
        other => other,
    };
    match kind {
        "gpu" => format!("{name} graphics"),
        "os" => format!("{name} systems"),
        "cpu" => format!("{name} processors"),
        _ => name.to_string(),
    }
}

fn variant_label(variant: &str) -> &str {
    match variant {
        "official" => "Valve's Proton",
        "experimental" => "Proton Experimental",
        "ge" => "GE-Proton",
        "cachyos" => "proton-cachyos",
        "notListed" => "Other build (not listed)",
        "older" => "Older Proton",
        "native" => "Native Linux",
        other => other,
    }
}

fn share(count: u32, reports: u32) -> f64 {
    if reports == 0 {
        0.0
    } else {
        f64::from(count) / f64::from(reports)
    }
}

/// An option's use among all reports and among systems like this one:
/// `{"count","reports","share","similar":[{"group","label","count",
/// "reports","share"}],"like":{...}}`; `like` is the first group of this
/// computer's with enough reports (else all reports, group "all").
pub fn usage(game: &Game, opt: &Opt, groups: &[String]) -> Value {
    let similar: Vec<Value> = groups
        .iter()
        .filter_map(|g| {
            let reports = *game.groups.get(g)?;
            (reports >= MIN_GROUP).then(|| {
                let count = opt.by.get(g).copied().unwrap_or(0);
                json!({"group": g, "label": group_label(g), "count": count, "reports": reports, "share": share(count, reports)})
            })
        })
        .collect();
    let all = json!({"group": "all", "label": "all reports", "count": opt.count, "reports": game.reports, "share": share(opt.count, game.reports)});
    let like = similar.first().cloned().unwrap_or_else(|| all.clone());
    json!({"count": opt.count, "reports": game.reports, "share": share(opt.count, game.reports), "similar": similar, "like": like})
}

/// The option as launch option text.
fn text_of(opt: &Opt) -> String {
    match (opt.kind.as_str(), &opt.value) {
        ("env", Some(v)) => format!("{}={v}", opt.name),
        _ => opt.name.clone(),
    }
}

/// "What others use" for the suggestions answer: `{"title","reports",
/// "export","months","source","groups":[..],"proton":[{"variant","label",
/// "count","share"}],"options":[{"kind","name","value","text","usage",
/// "check"}]}`. Options are sorted by their share among systems like this
/// one; each is checked for this game's build (`check` as one token of
/// launch_check), so an outdated one is flagged, never recommended.
pub fn others(meta: &Meta, game: &Game, groups: &[String], ctx: &Ctx) -> Value {
    let mut options: Vec<(f64, Value)> = game
        .options
        .iter()
        .map(|o| {
            let use_ = usage(game, o, groups);
            let rank = use_["like"]["share"].as_f64().unwrap_or(0.0);
            let kind: &'static str = match o.kind.as_str() {
                "env" => "env",
                "wrapper" => "wrapper",
                _ => "arg",
            };
            let value = o.value.clone().unwrap_or_default();
            let text = text_of(o);
            let check = launch_check::check_word(kind, &o.name, &value, &text, (0, text.len()), ctx);
            (rank, json!({"kind": o.kind, "name": o.name, "value": value, "text": text, "usage": use_, "check": check.to_json()}))
        })
        .collect();
    options.sort_by(|a, b| b.0.total_cmp(&a.0));
    options.truncate(SHOWN);
    json!({
        "title": game.title,
        "reports": game.reports,
        "export": meta.export,
        "months": meta.months,
        "source": meta.source,
        "groups": groups.iter().filter(|g| game.groups.get(*g).is_some_and(|n| *n >= MIN_GROUP)).map(|g| json!({"group": g, "label": group_label(g), "reports": game.groups[g]})).collect::<Vec<_>>(),
        "proton": game.proton.iter().map(|v| json!({"variant": v.variant, "label": variant_label(&v.variant), "count": v.count, "share": share(v.count, game.reports)})).collect::<Vec<_>>(),
        "options": options.into_iter().map(|(_, v)| v).collect::<Vec<_>>(),
    })
}

/// The share among systems like this one of a ProtonDB option that a
/// suggestion's option contains (by env name or wrapper program).
pub fn popularity(game: &Game, groups: &[String], option: &str) -> Option<Value> {
    let words: Vec<&str> = option.split_whitespace().collect();
    let found = game.options.iter().filter(|o| match o.kind.as_str() {
        "env" => words.iter().any(|w| w.split_once('=').is_some_and(|(n, _)| n == o.name)),
        "wrapper" => words.iter().any(|w| crate::launch_options::program_name(w) == o.name),
        _ => false,
    });
    found.map(|o| usage(game, o, groups)).max_by(|a, b| a["like"]["share"].as_f64().unwrap_or(0.0).total_cmp(&b["like"]["share"].as_f64().unwrap_or(0.0)))
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::launch_check::Family;

    /// Forza Horizon 6 as the 2026-11-02 export has it, trimmed.
    pub const FORZA: &str = r#"{"source":"ProtonDB data export (github.com/bdefore/protondb-data), ODbL 1.0","export":"2026-11-02","months":24,"games":{
      "2483190":{"title":"Forza Horizon 6","reports":709,
        "groups":{"cpu:amd":529,"cpu:deck":40,"cpu:intel":137,"gpu:amd":282,"gpu:deck":40,"gpu:intel":12,"gpu:nvidia":367,"os:arch":136,"os:bazzite":85,"os:cachyos":249,"os:debian":64,"os:fedora":86,"os:gentoo":3,"os:nixos":10,"os:other":23,"os:steamos":43,"os:suse":10},
        "proton":[{"count":385,"variant":"notListed"},{"count":133,"variant":"official"},{"count":94,"variant":"experimental"},{"count":92,"variant":"ge"}],
        "options":[
          {"by":{"cpu:amd":288,"cpu:intel":87,"gpu:amd":51,"gpu:intel":6,"gpu:nvidia":315,"os:arch":76,"os:bazzite":48,"os:cachyos":166,"os:debian":36,"os:fedora":33,"os:gentoo":1,"os:nixos":5,"os:other":6,"os:suse":5},"count":376,"kind":"env","name":"VKD3D_CONFIG","value":"enable_experimental_features,descriptor_heap"},
          {"by":{"cpu:amd":229,"cpu:intel":72,"gpu:amd":29,"gpu:intel":3,"gpu:nvidia":269,"os:arch":61,"os:bazzite":40,"os:cachyos":137,"os:debian":24,"os:fedora":27,"os:gentoo":1,"os:nixos":5,"os:other":4,"os:suse":3},"count":302,"kind":"env","name":"PROTON_VKD3D_HEAP","value":"1"},
          {"by":{"cpu:amd":98,"cpu:deck":2,"cpu:intel":32,"gpu:amd":48,"gpu:deck":2,"gpu:intel":5,"gpu:nvidia":77,"os:arch":30,"os:bazzite":12,"os:cachyos":63,"os:debian":3,"os:fedora":14,"os:gentoo":1,"os:nixos":1,"os:other":3,"os:steamos":2,"os:suse":3},"count":132,"kind":"env","name":"PROTON_ENABLE_WAYLAND","value":"1"},
          {"by":{"gpu:amd":20,"gpu:nvidia":30,"os:cachyos":12},"count":54,"kind":"wrapper","name":"gamemoderun"},
          {"by":{"gpu:amd":15,"gpu:nvidia":20},"count":38,"kind":"env","name":"PROTON_ENABLE_HDR","value":"1"}
        ]},
      "10":{"title":"Small","reports":3,"groups":{"gpu:amd":2},"proton":[],"options":[{"count":2,"kind":"wrapper","name":"mangohud","by":{"gpu:amd":2}}]}}}"#;

    pub fn fixture(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-pdb-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("protondb.json");
        std::fs::write(&path, FORZA).unwrap();
        path
    }

    fn ctx(family: Family, gpu: &str) -> Ctx {
        Ctx {
            family,
            tool: "proton-cachyos-slr".into(),
            sure: true,
            gpus: vec![gpu.into()],
            nvidia_major: None,
            tools: vec!["gamemoderun".into()],
            ananicy: false,
            cachyos: true,
            steam_form: true,
        }
    }

    #[test]
    fn shares_follow_systems_like_this_one() {
        let path = fixture("share");
        let (meta, game) = load(&path, "2483190").unwrap();
        assert_eq!((meta.export.as_str(), game.reports), ("2026-11-02", 709));
        assert!(load(&path, "999").is_none());
        // An AMD computer on CachyOS: the VKD3D options are NVIDIA's habit.
        let amd = groups_of("amd", "cachyos", "amd");
        let use_ = usage(&game, &game.options[0], &amd);
        assert_eq!(use_["like"]["group"], "gpu:amd");
        assert_eq!((use_["like"]["count"].as_u64(), use_["like"]["reports"].as_u64()), (Some(51), Some(282)));
        assert!(use_["like"]["share"].as_f64().unwrap() < 0.2);
        assert!(use_["share"].as_f64().unwrap() > 0.5);
        assert_eq!(use_["similar"].as_array().unwrap().len(), 3);
        let nvidia = groups_of("nvidia", "cachyos", "amd");
        let use_ = usage(&game, &game.options[1], &nvidia);
        assert_eq!((use_["like"]["count"].as_u64(), use_["like"]["reports"].as_u64()), (Some(269), Some(367)));
        // Too few reports in a group: the next group, else all reports.
        let use_ = usage(&game, &game.options[0], &groups_of("intel", "gentoo", ""));
        assert_eq!(use_["like"]["group"], "gpu:intel");
        let (_, small) = load(&path, "10").unwrap();
        assert_eq!(usage(&small, &small.options[0], &amd)["like"]["group"], "all");
        // "What others use" on AMD/proton-cachyos: sorted by the AMD share,
        // each checked for this build.
        let o = others(&meta, &game, &amd, &ctx(Family::CachyOs, "amd"));
        let names: Vec<&str> = o["options"].as_array().unwrap().iter().map(|x| x["name"].as_str().unwrap()).collect();
        assert_eq!(names, ["VKD3D_CONFIG", "PROTON_ENABLE_WAYLAND", "PROTON_VKD3D_HEAP", "gamemoderun", "PROTON_ENABLE_HDR"]);
        let check = |name: &str| o["options"].as_array().unwrap().iter().find(|x| x["name"] == name).unwrap()["check"].clone();
        assert_eq!(check("PROTON_VKD3D_HEAP")["status"], "outdated");
        assert_eq!(check("PROTON_ENABLE_HDR")["status"], "outdated");
        assert_eq!(check("PROTON_ENABLE_HDR")["replacement"], "DXVK_HDR=1");
        assert_eq!(check("VKD3D_CONFIG")["status"], "ok");
        assert!(!check("VKD3D_CONFIG")["explanation"].as_str().unwrap().is_empty());
        assert_eq!(o["proton"][0]["label"], "Other build (not listed)");
        assert_eq!(o["groups"][0]["group"], "gpu:amd");
        // On Valve's Proton the cachyos switch does nothing.
        let o = others(&meta, &game, &nvidia, &ctx(Family::Valve(11), "nvidia"));
        let heap = o["options"].as_array().unwrap().iter().find(|x| x["name"] == "PROTON_VKD3D_HEAP").unwrap();
        assert_eq!(heap["check"]["status"], "no_effect");
        // A suggestion's share.
        let p = popularity(&game, &amd, "PROTON_ENABLE_WAYLAND=1 %command%").unwrap();
        assert_eq!(p["like"]["count"], 48);
        assert!(popularity(&game, &amd, "mangohud %command%").is_none());
    }

    #[test]
    fn reads_the_gzip_extract() {
        use std::io::Write;
        let path = fixture("gz").with_extension("json.gz");
        let mut gz = flate2::write::GzEncoder::new(std::fs::File::create(&path).unwrap(), flate2::Compression::fast());
        gz.write_all(FORZA.as_bytes()).unwrap();
        gz.finish().unwrap();
        assert_eq!(load(&path, "2483190").unwrap().1.title, "Forza Horizon 6");
        // The shipped extract, when it is there.
        let shipped = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/data/protondb.json.gz"));
        if shipped.is_file() {
            let (meta, game) = load(shipped, "2483190").unwrap();
            assert!(game.reports > 100 && !meta.export.is_empty());
            assert!(game.groups.contains_key("gpu:nvidia"));
        }
    }
}
