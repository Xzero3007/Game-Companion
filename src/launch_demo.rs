//! Made-up launch option data for screenshots (`GC_DEMO=games,launch`,
//! `games,suggestions`, `games,proton`): a computer, the Proton builds on
//! it and each demo game's options. The checker, the suggestions and
//! ProtonDB's extract work on it as on real data; nothing is read from the
//! launchers and nothing is written.

use std::path::PathBuf;

use crate::launch_options::{parse, parse_own, Current, Tool};
use crate::system_info::{Display, Gpu, SystemInfo};

/// The demo game whose options the screenshots show (ProtonDB's extract has
/// reports for it).
pub const RACER: &str = "steam:2483190";

const RACER_OPTIONS: &str = "PROTON_DISABLE_HIDRAW=1 VKD3D_CONFIG=descriptor_heap,enable_experimental_features PROTON_VKD3D_HEAP=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%";

fn demo_has(word: &str) -> bool {
    std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|w| w == word))
}

/// The launcher counts as running with `GC_DEMO=...,launcherrunning`.
pub fn launcher_running() -> bool {
    demo_has("launcherrunning")
}

pub fn system() -> SystemInfo {
    SystemInfo {
        gpus: vec![Gpu { vendor: "nvidia".into(), driver: "nvidia".into(), card: "card1".into() }],
        nvidia_version: Some("580.95.05".into()),
        cpu: "AMD Ryzen 7 7800X3D 8-Core Processor".into(),
        threads: 16,
        ram_mb: 32_000,
        kernel: "6.18.2-2-cachyos".into(),
        tools: ["gamemoderun", "mangohud", "gamescope", "game-performance"].iter().map(|t| (t.to_string(), PathBuf::from("/usr/bin").join(t))).collect(),
        session: "wayland".into(),
        desktop: "KDE".into(),
        ntsync: true,
        display: Some(Display { name: "DP-2".into(), width: 3440, height: 1440, refresh: Some(144), hdr: true }),
        hdr_layer: false,
        os_id: "cachyos".into(),
        os_like: vec!["arch".into()],
        cpu_vendor: "amd".into(),
        ananicy: false,
        display_card: "card1".into(),
    }
}

pub fn tools() -> Vec<Tool> {
    let steam = |name: &str, label: &str| Tool {
        name: name.into(),
        label: label.into(),
        path: PathBuf::from("/home/me/.local/share/Steam/steamapps/common").join(label),
        source: "steam",
        kind: "proton",
        launchers: vec!["steam", "heroic"],
    };
    vec![
        steam("proton_10", "Proton 10.0"),
        steam("proton_9", "Proton 9.0"),
        steam("proton_experimental", "Proton - Experimental"),
        Tool {
            name: "GE-Proton10-25".into(),
            label: "GE-Proton10-25".into(),
            path: "/home/me/.local/share/Steam/compatibilitytools.d/GE-Proton10-25".into(),
            source: "custom",
            kind: "proton",
            launchers: vec!["steam", "heroic"],
        },
        Tool {
            name: "proton-cachyos-slr".into(),
            label: "proton-cachyos (Steam Linux Runtime)".into(),
            path: "/usr/share/steam/compatibilitytools.d/proton-cachyos-slr".into(),
            source: "system",
            kind: "proton",
            launchers: vec!["steam", "heroic"],
        },
        Tool {
            name: "Proton - GE-Proton9-27".into(),
            label: "GE-Proton9-27".into(),
            path: "/home/me/.config/heroic/tools/proton/GE-Proton9-27".into(),
            source: "heroic",
            kind: "proton",
            launchers: vec!["heroic"],
        },
        Tool {
            name: "Wine - Wine-GE-Proton8-26".into(),
            label: "Wine-GE-Proton8-26".into(),
            path: "/home/me/.config/heroic/tools/wine/Wine-GE-Proton8-26".into(),
            source: "heroic",
            kind: "wine",
            launchers: vec!["heroic"],
        },
        Tool {
            name: "wine-ge-8-26-x86_64".into(),
            label: "wine-ge-8-26-x86_64".into(),
            path: "/home/me/.local/share/lutris/runners/wine/wine-ge-8-26-x86_64".into(),
            source: "lutris",
            kind: "wine",
            launchers: vec!["lutris"],
        },
    ]
}

/// Steam's default for all games in the demo.
pub const STEAM_DEFAULT: &str = "proton_10";

/// A demo game's options as its launcher would keep them.
pub fn current(id: &str, own_command: Option<&str>) -> Current {
    let steam = |text: &str, tool: &str| Current {
        launcher: "steam".into(),
        supported: true,
        text: text.into(),
        spec: parse(text).unwrap_or_default(),
        file: Some("/home/me/.local/share/Steam/userdata/100/config/localconfig.vdf".into()),
        user: "100".into(),
        tool: tool.into(),
        global_tool: STEAM_DEFAULT.into(),
        proton: Some(true),
        ..Default::default()
    };
    // The demo's own entry lives only in memory, not in the settings.
    let own_command = own_command.or((id == "own:1").then_some("wine ~/Games/aion2/AION2.exe"));
    if let Some(command) = own_command {
        return Current {
            launcher: "own".into(),
            supported: true,
            text: command.into(),
            spec: parse_own(command).unwrap_or_default(),
            proton: Some(command.contains("proton") || command.contains("umu-run")),
            ..Default::default()
        };
    }
    match id {
        RACER => steam(RACER_OPTIONS, "proton-cachyos-slr"),
        "steam:2694490" => steam("gamemoderun %command% --nologo", "GE-Proton10-25"),
        "steam:1000001" => steam("", ""),
        "lutris:3" => {
            let text = "DXVK_ASYNC=1 mangohud";
            Current {
                launcher: "lutris".into(),
                supported: true,
                text: text.into(),
                spec: parse(text).unwrap_or_default(),
                file: Some("/home/me/.config/lutris/games/dungeon-crawler.yml".into()),
                tool: "wine-ge-8-26-x86_64".into(),
                proton: Some(false),
                runner: "wine".into(),
                ..Default::default()
            }
        }
        id if id.starts_with("heroic:") => Current {
            launcher: "heroic".into(),
            supported: true,
            file: Some("/home/me/.config/heroic/GamesConfig/demo.json".into()),
            tool: if id.contains("gog") { "Wine - Wine-GE-Proton8-26".into() } else { "Proton - GE-Proton9-27".into() },
            proton: Some(!id.contains("gog")),
            ..Default::default()
        },
        _ => Current { error: "This game has no launch options to set here".into(), ..Default::default() },
    }
}

/// Shows how a suggestion that does nothing with the game's build looks
/// (the backend marks such ones `available: false` with `unavailable_why`).
pub fn add_unavailable(answer: &mut serde_json::Value) {
    if let Some(list) = answer.get_mut("suggestions").and_then(serde_json::Value::as_array_mut) {
        list.push(serde_json::json!({
            "id": "demo_ntsync", "label": "NTSync",
            "explanation": "Faster thread sync in the kernel: smoother frame times.",
            "option": "PROTON_USE_NTSYNC=1 %command%", "recommended": false, "why": "", "warning": "",
            "group": "", "applied": false, "flavours": ["ge"], "popular": null, "available": false,
            "unavailable_why": "proton-cachyos uses NTSync by itself when /dev/ntsync is there (as GE-Proton10-10 and later do); this switch does nothing.",
        }));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::launch_check;
    use crate::launch_options;

    #[test]
    fn the_demo_shows_every_kind_of_status() {
        let tools = tools();
        let racer = current(RACER, None);
        let ctx = launch_check::context(&system(), &racer, &tools);
        let report = launch_check::check(&racer.text, &ctx).to_json(&racer.text);
        if std::env::var_os("GC_PRINT").is_some() {
            println!("{}", serde_json::to_string_pretty(&report).unwrap());
            let pdb = crate::protondb::load(&crate::protondb::data_path().unwrap(), "2483190");
            println!("{}", serde_json::to_string_pretty(&launch_check::suggestions_answer(&system(), &racer, &tools, pdb)).unwrap());
        }
        let statuses: Vec<&str> = report["tokens"].as_array().unwrap().iter().filter_map(|t| t["status"].as_str()).collect();
        assert!(statuses.contains(&"outdated"), "{statuses:?}");
        assert_eq!(launch_options::tool_in_use(&racer, &tools), "proton-cachyos-slr");
        // Heroic's own name for a build maps to the build.
        assert_eq!(launch_options::tool_name(&current("heroic:legendary:demo", None), &tools), "Proton - GE-Proton9-27");
        let usage = launch_options::usage_json(&[(RACER.into(), racer), ("steam:1000001".into(), current("steam:1000001", None))], &tools, STEAM_DEFAULT);
        assert_eq!(usage["games"][1]["inUse"], "proton_10");
        assert_eq!(usage["games"][1]["choice"], "");
    }
}
