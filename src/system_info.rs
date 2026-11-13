//! What this computer has, for the launch option suggestions: graphics
//! cards and driver, processor, memory, the gaming tools installed, the
//! session (Wayland or X11) and the main screen (size, refresh, HDR, from
//! KWin's own file). Only local files are read; nothing is run or sent.

use std::path::{Path, PathBuf};

use serde_json::{json, Value};

/// The tools a suggestion can use, by the program's name.
pub const TOOLS: &[&str] = &["gamemoderun", "mangohud", "gamescope", "obs-gamecapture", "prime-run"];

#[derive(Debug, Clone, PartialEq)]
pub struct Gpu {
    /// "nvidia", "amd", "intel" or "other".
    pub vendor: String,
    /// The kernel driver ("nvidia", "amdgpu", "i915", "xe", "nouveau", ...).
    pub driver: String,
    /// The DRM card ("card1").
    pub card: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Display {
    /// The connector ("DP-1", "HDMI-A-1").
    pub name: String,
    pub width: u32,
    pub height: u32,
    /// Refresh rate in Hz (KWin's file only).
    pub refresh: Option<u32>,
    /// HDR switched on in KDE's display settings.
    pub hdr: bool,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SystemInfo {
    pub gpus: Vec<Gpu>,
    /// The NVIDIA driver's version ("560.35.03").
    pub nvidia_version: Option<String>,
    pub cpu: String,
    pub threads: u32,
    pub ram_mb: u64,
    pub kernel: String,
    /// Installed tools from `TOOLS`, with where they were found.
    pub tools: Vec<(String, PathBuf)>,
    /// "wayland", "x11" or "".
    pub session: String,
    pub desktop: String,
    /// `/dev/ntsync` exists (the kernel's NT sync driver, Linux 6.14+).
    pub ntsync: bool,
    /// The main screen (KDE's primary, or the one chosen in Display).
    pub display: Option<Display>,
    /// A Vulkan HDR layer (vk-hdr-layer) is installed.
    pub hdr_layer: bool,
}

impl SystemInfo {
    pub fn has_tool(&self, name: &str) -> bool {
        self.tools.iter().any(|(n, _)| n == name)
    }

    pub fn has_gpu(&self, vendor: &str) -> bool {
        self.gpus.iter().any(|g| g.vendor == vendor)
    }

    /// NVIDIA's own driver (not nouveau).
    pub fn nvidia_driver(&self) -> bool {
        self.gpus.iter().any(|g| g.vendor == "nvidia" && g.driver == "nvidia") || self.nvidia_version.is_some()
    }

    /// An NVIDIA card next to another one (a laptop's hybrid graphics).
    pub fn hybrid(&self) -> bool {
        self.has_gpu("nvidia") && self.gpus.iter().any(|g| g.vendor != "nvidia")
    }

    pub fn to_json(&self) -> Value {
        json!({
            "gpus": self.gpus.iter().map(|g| json!({"vendor": g.vendor, "driver": g.driver, "card": g.card})).collect::<Vec<_>>(),
            "nvidiaVersion": self.nvidia_version.clone().unwrap_or_default(),
            "cpu": self.cpu,
            "threads": self.threads,
            "ramMb": self.ram_mb,
            "kernel": self.kernel,
            "tools": self.tools.iter().map(|(n, _)| n.clone()).collect::<Vec<_>>(),
            "session": self.session,
            "desktop": self.desktop,
            "ntsync": self.ntsync,
            "display": self.display.as_ref().map(|d| json!({
                "name": d.name, "width": d.width, "height": d.height,
                "refresh": d.refresh.unwrap_or(0), "hdr": d.hdr,
            })).unwrap_or(Value::Null),
            "hdrLayer": self.hdr_layer,
        })
    }
}

/// Where to look: `root` is "/" (a test's folder otherwise), `config` the
/// user's config folder (for kwinoutputconfig.json), `env` the environment,
/// `screen` the screen chosen in Display ("" = KDE's primary).
pub fn detect(root: &Path, config: &Path, env: &dyn Fn(&str) -> Option<String>, screen: &str) -> SystemInfo {
    let at = |p: &str| root.join(p.trim_start_matches('/'));
    let read = |p: &str| std::fs::read_to_string(at(p)).unwrap_or_default();
    let mut info = SystemInfo { gpus: gpus(&at("/sys/class/drm")), ..Default::default() };
    let nvidia = read("/proc/driver/nvidia/version");
    info.nvidia_version = nvidia.lines().find_map(|l| {
        // "... Kernel Module  560.35.03 ..." or "... Open Kernel Module for x86_64  580.95.05 ...".
        let rest = l.split("Kernel Module").nth(1)?;
        rest.split_whitespace().find(|w| w.contains('.') && w.chars().all(|c| c.is_ascii_digit() || c == '.')).map(str::to_string)
    });
    let cpuinfo = read("/proc/cpuinfo");
    info.cpu = cpuinfo
        .lines()
        .find_map(|l| l.strip_prefix("model name").and_then(|r| r.split_once(':')).map(|(_, v)| v.trim().to_string()))
        .unwrap_or_default();
    info.threads = cpuinfo.lines().filter(|l| l.starts_with("processor")).count() as u32;
    info.ram_mb = read("/proc/meminfo")
        .lines()
        .find_map(|l| l.strip_prefix("MemTotal:").and_then(|r| r.split_whitespace().next()).and_then(|n| n.parse::<u64>().ok()))
        .map(|kb| kb / 1024)
        .unwrap_or(0);
    info.kernel = read("/proc/sys/kernel/osrelease").trim().to_string();
    let path = env("PATH").unwrap_or_else(|| "/usr/local/bin:/usr/bin:/bin".into());
    for tool in TOOLS {
        let found = path.split(':').filter(|d| d.starts_with('/')).map(|d| at(d).join(tool)).find(|p| is_executable(p));
        if let Some(found) = found {
            info.tools.push((tool.to_string(), found));
        }
    }
    info.session = match env("XDG_SESSION_TYPE").as_deref() {
        Some("wayland") => "wayland".into(),
        Some("x11") => "x11".into(),
        _ if env("WAYLAND_DISPLAY").is_some_and(|w| !w.is_empty()) => "wayland".into(),
        _ if env("DISPLAY").is_some_and(|d| !d.is_empty()) => "x11".into(),
        _ => String::new(),
    };
    info.desktop = env("XDG_CURRENT_DESKTOP").unwrap_or_default();
    info.ntsync = at("/dev/ntsync").exists();
    info.hdr_layer = ["/usr/share/vulkan/implicit_layer.d", "/etc/vulkan/implicit_layer.d"]
        .iter()
        .filter_map(|d| std::fs::read_dir(at(d)).ok())
        .flat_map(|d| d.flatten())
        .any(|e| e.file_name().to_string_lossy().to_ascii_lowercase().contains("hdr"));
    let connected = connected_outputs(&at("/sys/class/drm"));
    info.display = main_display(&config.join("kwinoutputconfig.json"), &connected, screen);
    info
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// The graphics cards: `cardN` folders (not their connectors).
fn gpus(drm: &Path) -> Vec<Gpu> {
    let Ok(entries) = std::fs::read_dir(drm) else { return Vec::new() };
    let mut cards: Vec<Gpu> = entries
        .flatten()
        .filter_map(|e| {
            let card = e.file_name().to_string_lossy().into_owned();
            if !card.starts_with("card") || card.contains('-') {
                return None;
            }
            let device = e.path().join("device");
            let vendor = std::fs::read_to_string(device.join("vendor")).ok()?;
            let vendor = match vendor.trim() {
                "0x10de" => "nvidia",
                "0x1002" => "amd",
                "0x8086" => "intel",
                _ => "other",
            };
            let driver = std::fs::read_link(device.join("driver"))
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
                .unwrap_or_default();
            Some(Gpu { vendor: vendor.into(), driver, card })
        })
        .collect();
    cards.sort_by(|a, b| a.card.cmp(&b.card));
    cards
}

/// Connected outputs with their preferred size: `cardN-<connector>/status`
/// and the first line of `modes`.
fn connected_outputs(drm: &Path) -> Vec<(String, Option<(u32, u32)>)> {
    let Ok(entries) = std::fs::read_dir(drm) else { return Vec::new() };
    let mut out: Vec<(String, Option<(u32, u32)>)> = entries
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            let (card, connector) = name.split_once('-')?;
            if !card.starts_with("card") {
                return None;
            }
            let status = std::fs::read_to_string(e.path().join("status")).ok()?;
            if status.trim() != "connected" {
                return None;
            }
            let mode = std::fs::read_to_string(e.path().join("modes")).ok().and_then(|m| {
                let (w, h) = m.lines().next()?.split_once('x')?;
                Some((w.trim().parse().ok()?, h.trim().trim_end_matches(|c: char| !c.is_ascii_digit()).parse().ok()?))
            });
            Some((connector.to_string(), mode))
        })
        .collect();
    out.sort();
    out
}

/// The main screen: the chosen one, else KWin's primary for the connected
/// outputs (as `NativeWindow::kdePrimary`), else the first connected one;
/// mode and HDR from KWin's file when it knows the output.
fn main_display(kwin: &Path, connected: &[(String, Option<(u32, u32)>)], screen: &str) -> Option<Display> {
    let parts: Value = std::fs::read_to_string(kwin).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(Value::Null);
    let section = |name: &str| -> Vec<Value> {
        parts
            .as_array()
            .and_then(|a| a.iter().find(|p| p["name"] == name))
            .and_then(|p| p["data"].as_array().cloned())
            .unwrap_or_default()
    };
    let outputs = section("outputs");
    let setups = section("setups");
    let connector = |i: &Value| -> Option<String> {
        let index = i["outputIndex"].as_u64()? as usize;
        outputs.get(index)?["connectorName"].as_str().map(str::to_string)
    };
    let names: std::collections::BTreeSet<String> = connected.iter().map(|(n, _)| n.clone()).collect();
    let mut primary = None;
    for setup in &setups {
        let list = setup["outputs"].as_array().cloned().unwrap_or_default();
        let enabled: Vec<&Value> = list.iter().filter(|e| e["enabled"].as_bool().unwrap_or(true)).collect();
        let set: std::collections::BTreeSet<String> = enabled.iter().filter_map(|e| connector(e)).collect();
        if !set.is_empty() && set == names {
            primary = enabled.iter().min_by_key(|e| e["priority"].as_i64().unwrap_or(i64::MAX)).and_then(|e| connector(e));
            break;
        }
    }
    let chosen = Some(screen.to_string())
        .filter(|s| !s.is_empty() && names.contains(s))
        .or(primary)
        .or_else(|| connected.first().map(|(n, _)| n.clone()))?;
    let mut display = Display { name: chosen.clone(), ..Default::default() };
    if let Some((w, h)) = connected.iter().find(|(n, _)| *n == chosen).and_then(|(_, m)| *m) {
        display.width = w;
        display.height = h;
    }
    if let Some(output) = outputs.iter().find(|o| o["connectorName"] == chosen.as_str()) {
        let mode = &output["mode"];
        if let (Some(w), Some(h)) = (mode["width"].as_u64(), mode["height"].as_u64()) {
            display.width = w as u32;
            display.height = h as u32;
        }
        // KWin keeps millihertz.
        display.refresh = mode["refreshRate"].as_u64().filter(|r| *r > 0).map(|r| ((r + 500) / 1000) as u32);
        display.hdr = output["highDynamicRange"].as_bool().unwrap_or(false);
    }
    (display.width > 0 && display.height > 0).then_some(display)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-sys-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write(path: &Path, text: &str) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn tool(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        write(path, "#!/bin/sh\n");
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }

    /// A made-up laptop: Intel plus NVIDIA, two screens, some tools.
    pub fn fake_root(name: &str) -> PathBuf {
        let root = temp(name);
        let drm = root.join("sys/class/drm");
        for (card, vendor, driver) in [("card0", "0x8086", "i915"), ("card1", "0x10de", "nvidia")] {
            write(&drm.join(card).join("device/vendor"), &format!("{vendor}\n"));
            std::fs::create_dir_all(root.join("drivers").join(driver)).unwrap();
            std::os::unix::fs::symlink(root.join("drivers").join(driver), drm.join(card).join("device/driver")).unwrap();
        }
        write(&drm.join("card1-DP-1/status"), "connected\n");
        write(&drm.join("card1-DP-1/modes"), "3440x1440\n1920x1080\n");
        write(&drm.join("card1-DP-2/status"), "connected\n");
        write(&drm.join("card1-DP-2/modes"), "2560x1440\n");
        write(&drm.join("card0-eDP-1/status"), "disconnected\n");
        write(&root.join("proc/driver/nvidia/version"), "NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  580.95.05  Release Build\n");
        write(&root.join("proc/cpuinfo"), "processor\t: 0\nmodel name\t: AMD Ryzen 7 7800X3D 8-Core Processor\nprocessor\t: 1\nmodel name\t: AMD Ryzen 7 7800X3D 8-Core Processor\n");
        write(&root.join("proc/meminfo"), "MemTotal:       32768000 kB\nMemFree: 1 kB\n");
        write(&root.join("proc/sys/kernel/osrelease"), "6.17.1-arch1-1\n");
        write(&root.join("dev/ntsync"), "");
        write(&root.join("usr/share/vulkan/implicit_layer.d/VkLayer_hdr_wsi.x86_64.json"), "{}");
        tool(&root.join("usr/bin/gamemoderun"));
        tool(&root.join("usr/bin/gamescope"));
        tool(&root.join("usr/bin/prime-run"));
        write(&root.join("usr/bin/mangohud"), "not executable");
        let kwin = r#"[{"name":"outputs","data":[
            {"connectorName":"DP-1","mode":{"width":3440,"height":1440,"refreshRate":100000},"highDynamicRange":false},
            {"connectorName":"DP-2","mode":{"width":2560,"height":1440,"refreshRate":164958},"highDynamicRange":true}]},
            {"name":"setups","data":[{"outputs":[{"outputIndex":0,"enabled":true,"priority":2},{"outputIndex":1,"enabled":true,"priority":1}]}]}]"#;
        write(&root.join("home/.config/kwinoutputconfig.json"), kwin);
        root
    }

    pub fn fake_env(key: &str) -> Option<String> {
        match key {
            "PATH" => Some("/usr/local/bin:/usr/bin".into()),
            "XDG_SESSION_TYPE" => Some("wayland".into()),
            "XDG_CURRENT_DESKTOP" => Some("KDE".into()),
            _ => None,
        }
    }

    #[test]
    fn reads_a_made_up_computer() {
        let root = fake_root("laptop");
        let info = detect(&root, &root.join("home/.config"), &fake_env, "");
        assert_eq!(info.gpus.len(), 2);
        assert_eq!((info.gpus[1].vendor.as_str(), info.gpus[1].driver.as_str()), ("nvidia", "nvidia"));
        assert_eq!(info.gpus[0].driver, "i915");
        assert!(info.nvidia_driver() && info.hybrid());
        assert_eq!(info.nvidia_version.as_deref(), Some("580.95.05"));
        assert_eq!(info.cpu, "AMD Ryzen 7 7800X3D 8-Core Processor");
        assert_eq!(info.threads, 2);
        assert_eq!(info.ram_mb, 32000);
        assert_eq!(info.kernel, "6.17.1-arch1-1");
        let tools: Vec<&str> = info.tools.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(tools, vec!["gamemoderun", "gamescope", "prime-run"]);
        assert_eq!((info.session.as_str(), info.desktop.as_str()), ("wayland", "KDE"));
        assert!(info.ntsync && info.hdr_layer);
        // KDE's primary is DP-2 (priority 1), with HDR on.
        assert_eq!(info.display, Some(Display { name: "DP-2".into(), width: 2560, height: 1440, refresh: Some(165), hdr: true }));
        // The screen chosen in Display wins.
        let info = detect(&root, &root.join("home/.config"), &fake_env, "DP-1");
        assert_eq!(info.display.as_ref().map(|d| (d.width, d.refresh, d.hdr)), Some((3440, Some(100), false)));
        let v = info.to_json();
        assert_eq!(v["display"]["name"], "DP-1");
        assert_eq!(v["tools"][0], "gamemoderun");
    }

    #[test]
    fn copes_with_nothing() {
        let root = temp("empty");
        let info = detect(&root, &root, &|_| None, "");
        assert_eq!(info, SystemInfo::default());
        assert_eq!(info.to_json()["display"], Value::Null);
    }

    #[test]
    fn sysfs_alone_gives_a_size() {
        let root = temp("sysfs");
        write(&root.join("sys/class/drm/card0-HDMI-A-1/status"), "connected\n");
        write(&root.join("sys/class/drm/card0-HDMI-A-1/modes"), "1920x1080\n");
        let info = detect(&root, &root, &|_| None, "");
        assert_eq!(info.display, Some(Display { name: "HDMI-A-1".into(), width: 1920, height: 1080, refresh: None, hdr: false }));
    }
}
