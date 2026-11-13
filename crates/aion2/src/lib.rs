//! The AION 2 module's parser: what the game's server sends, read into
//! fights, players and the world around the player.
//!
//! Taken from the A2Tools DPS Meter by taengu (GPL-3.0,
//! https://github.com/taengu/A2Tools-DPS-Meter, v2.0.80) with the
//! Clicktrough build's changes (Xzero3007/A2Tools-DPS-Meter_Clicktrough).
//! The files keep their own structure, so changes from there can be taken
//! over again. It only reads: nothing here sends anything to the game or
//! its servers.
//!
//! The `live` feature adds the capture (libpcap, loaded at run time) and the
//! dispatcher that feeds the parser; without it the crate is the parser
//! alone (tests, replays).

pub mod capture;
pub mod clock;
pub mod combat;
pub mod decoders;
pub mod entity;
pub mod i18n;
pub mod history;
pub mod link;
pub mod supporters;
pub mod world;
#[cfg(feature = "live")]
pub mod engine;
#[cfg(feature = "live")]
pub mod platform;

/// The folder with the game's tables (skills, NPCs, maps), as shipped.
pub fn data_dir() -> std::path::PathBuf {
    if let Some(dir) = std::env::var_os("GC_AION2_DATA") {
        return dir.into();
    }
    let installed = std::path::Path::new("/usr/share/game-companion/aion2");
    if installed.is_dir() {
        return installed.into();
    }
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("data")
}

/// A skill's picture on the game's icon server, as the meter's skillIcons.js
/// worked it out: "" when none is known (the panel draws a wand), "basic"
/// for a basic attack (crossed swords), else the icon's file name.
pub fn skill_icon(code: i64) -> String {
    static MAP: std::sync::OnceLock<std::collections::HashMap<String, String>> = std::sync::OnceLock::new();
    let map = MAP.get_or_init(|| {
        std::fs::read_to_string(data_dir().join("skill_icons.json"))
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default()
    });
    skill_icon_in(code, map)
}

fn skill_icon_in(code: i64, map: &std::collections::HashMap<String, String>) -> String {
    if code <= 0 {
        return String::new();
    }
    let mut code = code.to_string();
    if code.len() > 8 {
        code.truncate(8);
    }
    while code.len() < 8 {
        code.push('0');
    }
    // Theostones: 30 + quality + icon number (decimal, named in hex).
    if let Some(rest) = code.strip_prefix("30") {
        let n: u32 = rest[3..5].parse().unwrap_or(0);
        return if n > 0 { format!("Icon_Item_Usable_Godstone_WP_r_{n:03x}") } else { String::new() };
    }
    let (prefix, mid) = (&code[0..2], &code[2..6]);
    if ("11"..="18").contains(&prefix) && mid == "0000" && &code[6..] != "00" {
        return "basic".into();
    }
    if code.starts_with("1000") || code.starts_with("1699") {
        return "basic".into();
    }
    if let Some(name) = map.get(&code[0..4]) {
        return name.clone();
    }
    let class = match prefix {
        "11" => "GL",
        "12" => "TE",
        "13" => "AS",
        "14" => "RA",
        "15" => "SO",
        "16" => "EL",
        "17" => "CL",
        "18" => "CH",
        "19" => "GT",
        _ => return String::new(),
    };
    let sub: u32 = code[2..4].parse().unwrap_or(0);
    format!("ICON_{class}_SKILL_{sub:03}")
}

/// A class's English name: the game's tables name them in Korean
/// (e.g. 궁성, "Ranger").
pub fn job_name(job: &str) -> String {
    let english = match job.trim() {
        "검성" => "Gladiator",
        "수호성" => "Templar",
        "살성" => "Assassin",
        "궁성" => "Ranger",
        "마도성" => "Sorcerer",
        "정령성" => "Spiritmaster",
        "치유성" => "Cleric",
        "호법성" => "Chanter",
        other => return other.to_string(),
    };
    english.to_string()
}

#[cfg(test)]
mod skill_icon_tests {
    use super::*;

    #[test]
    fn skill_icons_as_the_meter_found_them() {
        let map: std::collections::HashMap<String, String> = [("1401".to_string(), "ICON_RA_SKILL_007".to_string())].into();
        assert_eq!(skill_icon_in(14010100, &map), "ICON_RA_SKILL_007");
        assert_eq!(skill_icon_in(14000001, &map), "basic");
        assert_eq!(skill_icon_in(10001234, &map), "basic");
        assert_eq!(skill_icon_in(14230000, &map), "ICON_RA_SKILL_023");
        assert_eq!(skill_icon_in(30001120, &map), "Icon_Item_Usable_Godstone_WP_r_00c");
        assert_eq!(skill_icon_in(77000000, &map), "");
        assert_eq!(skill_icon_in(0, &map), "");
        assert!(!skill_icon(16000000).is_empty());
    }
}
