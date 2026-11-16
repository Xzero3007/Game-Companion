//! Proton downloads (MN, 2026-11-16: "ja", plan in the project folder
//! `proton-download/plan.md`): GE-Proton and Proton-CachyOS from their own
//! GitHub releases, and nothing else. The release list comes from
//! api.github.com (those two repositories only, at most every 6 hours
//! unless asked); a download goes from the release's own download address
//! through GitHub's download server (the redirect is checked before
//! anything is fetched), is checked against the release's checksum and
//! unpacked by tar into a hidden folder beside the target, renamed only at
//! the end. Targets: Steam's compatibilitytools.d (the folder Steam really
//! uses) and Heroic's tools/proton. curl and tar end with the app; their
//! half-done files are removed then and at the next look.
//!
//! The pacman package proton-cachyos is only compared with the package
//! list on disk (`pacman -Si`, no network): updating it is the system's.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};
use sha2::{Digest, Sha256, Sha512};

/// The installed Proton list must be read again (an install or removal).
pub static TOOLS_STALE: AtomicBool = AtomicBool::new(false);
/// A running job should stop (Cancel, or the app quits).
static CANCEL: AtomicBool = AtomicBool::new(false);
/// The curl or tar running for a job, to end it at once on quit.
static CHILD: AtomicI32 = AtomicI32::new(0);

/// How long a release list is kept before GitHub is asked again.
pub const KEEP_LIST: Duration = Duration::from_secs(6 * 3600);
/// Prefix of the folder a download is unpacked into.
const PARTIAL: &str = ".gc-partial-";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flavour {
    Ge,
    Cachy,
}

impl Flavour {
    pub const ALL: [Flavour; 2] = [Flavour::Ge, Flavour::Cachy];

    pub fn id(self) -> &'static str {
        match self {
            Flavour::Ge => "ge",
            Flavour::Cachy => "cachyos",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|f| f.id() == id)
    }

    pub fn repo(self) -> &'static str {
        match self {
            Flavour::Ge => "GloriousEggroll/proton-ge-custom",
            Flavour::Cachy => "CachyOS/proton-cachyos",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Flavour::Ge => "GE-Proton",
            Flavour::Cachy => "Proton-CachyOS",
        }
    }

    /// What it is, in plain words.
    pub fn about(self) -> &'static str {
        match self {
            Flavour::Ge => "Valve's Proton with extra game fixes and video codecs from GloriousEggroll. Worth having when a game makes trouble with Valve's Proton or the release notes name it.",
            Flavour::Cachy => "Proton tuned by CachyOS: newer Wine and DXVK, Wayland and HDR support, fixes ahead of Valve. The Steam Linux Runtime build (SLR) from GitHub, apart from the pacman package.",
        }
    }

    fn api_url(self) -> String {
        format!("https://api.github.com/repos/{}/releases?per_page=8", self.repo())
    }

    /// A folder name this flavour's downloads have.
    pub fn owns(self, folder: &str) -> bool {
        match self {
            Flavour::Ge => folder.starts_with("GE-Proton"),
            Flavour::Cachy => folder.starts_with("proton-cachyos-") && folder.contains("x86_64"),
        }
    }
}

// ----------------------------------------------------------- releases ----

#[derive(Debug, Clone, PartialEq)]
pub struct Asset {
    pub name: String,
    pub url: String,
    pub size: u64,
    /// GitHub's own "sha256:<hex>", if the release has it.
    pub digest: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Release {
    pub tag: String,
    pub name: String,
    pub published: String,
    pub body: String,
    pub page: String,
    pub assets: Vec<Asset>,
}

fn safe_tag(tag: &str) -> bool {
    !tag.is_empty() && tag.len() < 100 && tag.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b)) && !tag.contains("..")
}

/// The address a release's file must come from.
pub fn download_ok(flavour: Flavour, url: &str) -> bool {
    let Some(rest) = url.strip_prefix(&format!("https://github.com/{}/releases/download/", flavour.repo())) else { return false };
    let mut parts = rest.split('/');
    let (Some(tag), Some(file), None) = (parts.next(), parts.next(), parts.next()) else { return false };
    safe_tag(tag) && safe_tag(file)
}

/// The release's page on GitHub (opened in the browser only on a click).
pub fn release_page_ok(url: &str) -> bool {
    Flavour::ALL.iter().any(|f| {
        url.strip_prefix(&format!("https://github.com/{}/releases/tag/", f.repo())).is_some_and(safe_tag)
    })
}

/// Where GitHub sends a release download: its own download servers only.
pub fn redirect_ok(url: &str) -> bool {
    const HOSTS: [&str; 2] = ["https://objects.githubusercontent.com/", "https://release-assets.githubusercontent.com/"];
    HOSTS.iter().any(|h| url.starts_with(h)) && url.len() < 8192 && url.bytes().all(|b| b.is_ascii_graphic())
}

/// Reads GitHub's release list: published releases only (no drafts or
/// pre-releases), with their files from this repository.
pub fn parse_releases(flavour: Flavour, text: &str) -> Result<Vec<Release>, String> {
    let list: Value = serde_json::from_str(text).map_err(|_| "GitHub's answer couldn't be read".to_string())?;
    let Some(list) = list.as_array() else {
        let why = list.get("message").and_then(Value::as_str).unwrap_or("");
        return Err(if why.contains("rate limit") { "GitHub asks to wait (too many looks in an hour)".into() } else { "GitHub's answer couldn't be read".into() });
    };
    let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let mut out = Vec::new();
    for r in list {
        if r.get("draft").and_then(Value::as_bool) == Some(true) || r.get("prerelease").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        let tag = s(r, "tag_name");
        if !safe_tag(&tag) {
            continue;
        }
        let page = s(r, "html_url");
        let assets = r
            .get("assets")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|a| {
                        let url = s(a, "browser_download_url");
                        let name = s(a, "name");
                        (download_ok(flavour, &url) && safe_tag(&name)).then(|| Asset {
                            name,
                            url,
                            size: a.get("size").and_then(Value::as_u64).unwrap_or(0),
                            digest: a.get("digest").and_then(Value::as_str).map(str::to_string),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        out.push(Release {
            name: s(r, "name"),
            published: s(r, "published_at"),
            body: s(r, "body").chars().take(20_000).collect(),
            page: if release_page_ok(&page) { page } else { String::new() },
            tag,
            assets,
        });
    }
    Ok(out)
}

/// Whether the CPU can run x86-64-v3 builds (AVX2 and friends).
pub fn cpu_v3(cpuinfo: &str) -> bool {
    let Some(flags) = cpuinfo.lines().find_map(|l| l.strip_prefix("flags").and_then(|r| r.split_once(':')).map(|(_, f)| f)) else { return false };
    let flags: Vec<&str> = flags.split_whitespace().collect();
    ["avx2", "bmi1", "bmi2", "fma", "movbe", "f16c", "abm"].iter().all(|f| flags.contains(f))
}

/// The release's archive for this computer, and its checksum file.
pub fn pick_asset(flavour: Flavour, release: &Release, v3: bool) -> Option<(Asset, Option<Asset>)> {
    let archive = |a: &&Asset| a.name.ends_with(".tar.gz") || a.name.ends_with(".tar.xz") || a.name.ends_with(".tar.zst");
    let chosen = match flavour {
        Flavour::Ge => release.assets.iter().filter(archive).find(|a| a.name.starts_with("GE-Proton")),
        Flavour::Cachy => {
            let plain = |a: &&Asset| {
                let stem = a.name.split(".tar.").next().unwrap_or("");
                stem.ends_with("x86_64") && !stem.contains("arm") && !stem.contains("aarch")
            };
            let v3_build = |a: &&Asset| a.name.split(".tar.").next().unwrap_or("").ends_with("x86_64_v3");
            let cachy = release.assets.iter().filter(archive).filter(|a| a.name.starts_with("proton-cachyos"));
            if v3 {
                cachy.clone().find(v3_build).or_else(|| cachy.clone().find(plain))
            } else {
                cachy.clone().find(plain)
            }
        }
    }?;
    let sum = release
        .assets
        .iter()
        .find(|a| a.name == format!("{}.sha512sum", chosen.name))
        .or_else(|| {
            let stem = chosen.name.split(".tar.").next().unwrap_or("");
            release.assets.iter().find(|a| a.name == format!("{stem}.sha512sum"))
        })
        .or_else(|| release.assets.iter().find(|a| a.name.ends_with(".sha512sum") && release.assets.iter().filter(|b| b.name.ends_with(".sha512sum")).count() == 1))
        .cloned();
    Some((chosen.clone(), sum))
}

/// The SHA-512 for `file` from a `.sha512sum` file's text ("<hex>  <name>"
/// lines, or one hash alone).
pub fn sha512_from(text: &str, file: &str) -> Option<String> {
    let hex = |h: &str| h.len() == 128 && h.bytes().all(|b| b.is_ascii_hexdigit());
    let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    for line in &lines {
        let mut parts = line.split_whitespace();
        let (Some(h), name) = (parts.next(), parts.next()) else { continue };
        let name = name.map(|n| n.trim_start_matches('*').rsplit('/').next().unwrap_or(n));
        if hex(h) && name == Some(file) {
            return Some(h.to_ascii_lowercase());
        }
    }
    if lines.len() == 1 {
        let h = lines[0].split_whitespace().next()?;
        if hex(h) {
            return Some(h.to_ascii_lowercase());
        }
    }
    None
}

/// A version to compare: GE-Proton10-25 → (10, 25, 0);
/// cachyos-11.0-20261015-slr / proton-cachyos-11.0-20261015-slr-x86_64 →
/// (11, 0, 20261015).
pub fn version_key(flavour: Flavour, name: &str) -> Option<(u32, u32, u32)> {
    match flavour {
        Flavour::Ge => {
            let rest = name.strip_prefix("GE-Proton")?;
            let (major, minor) = rest.split_once('-')?;
            let minor: String = minor.chars().take_while(char::is_ascii_digit).collect();
            Some((major.parse().ok()?, minor.parse().ok()?, 0))
        }
        Flavour::Cachy => {
            let rest = name.strip_prefix("proton-").unwrap_or(name).strip_prefix("cachyos-")?;
            let mut parts = rest.split('-');
            let version = parts.next()?;
            let date: u32 = parts.next()?.parse().ok()?;
            let (major, minor) = version.split_once('.').unwrap_or((version, "0"));
            Some((major.parse().ok()?, minor.parse().unwrap_or(0), date))
        }
    }
}

/// The release notes for the app: Markdown taken down to plain lines, at
/// most `max` characters.
pub fn notes_text(body: &str, max: usize) -> String {
    let mut out = String::new();
    for line in body.lines() {
        let mut l = line.trim().trim_start_matches('#').trim().to_string();
        if let Some(rest) = l.strip_prefix("- ").or_else(|| l.strip_prefix("* ")) {
            l = format!("• {rest}");
        }
        l = l.replace("**", "").replace("__", "").replace('`', "");
        // [text](link) → text
        while let (Some(a), Some(b)) = (l.find("]("), l.find('[')) {
            let Some(c) = l[a..].find(')') else { break };
            if b > a {
                break;
            }
            l = format!("{}{}{}", &l[..b], &l[b + 1..a], &l[a + c + 1..]);
        }
        if l.is_empty() && out.ends_with("\n\n") {
            continue;
        }
        out.push_str(&l);
        out.push('\n');
        if out.chars().count() > max {
            let cut: String = out.chars().take(max).collect();
            return format!("{}…", cut.trim_end());
        }
    }
    out.trim().to_string()
}

/// The names of `games` the release notes mention (whole words, case
/// ignored; names shorter than 4 letters are left out).
pub fn mentions(body: &str, games: &[String]) -> Vec<String> {
    let text = body.to_lowercase();
    let mut found: Vec<String> = Vec::new();
    for game in games {
        let name = game.trim();
        let lower = name.to_lowercase();
        if lower.chars().filter(|c| c.is_alphanumeric()).count() < 4 || found.contains(&name.to_string()) {
            continue;
        }
        let hit = text.match_indices(&lower).any(|(i, m)| {
            let before = text[..i].chars().next_back();
            let after = text[i + m.len()..].chars().next();
            !before.is_some_and(char::is_alphanumeric) && !after.is_some_and(char::is_alphanumeric)
        });
        if hit {
            found.push(name.to_string());
        }
    }
    found
}

// ------------------------------------------------------------ places ----

#[derive(Debug, Clone, PartialEq)]
pub struct Target {
    /// "steam" or "heroic".
    pub id: &'static str,
    pub label: &'static str,
    pub dir: PathBuf,
}

/// Where a download can go: Steam's compatibilitytools.d in the Steam
/// folder Steam uses (the first one found, as the library does) and
/// Heroic's tools/proton when Heroic is there.
pub fn targets(home: &Path) -> Vec<Target> {
    let mut list = Vec::new();
    if let Some(root) = crate::games::steam_roots(home).into_iter().next() {
        list.push(Target { id: "steam", label: "Steam", dir: root.join("compatibilitytools.d") });
    }
    for base in [home.join(".config/heroic"), home.join(".var/app/com.heroicgameslauncher.hgl/config/heroic")] {
        if base.is_dir() {
            list.push(Target { id: "heroic", label: "Heroic", dir: base.join("tools/proton") });
            break;
        }
    }
    list
}

#[derive(Debug, Clone, PartialEq)]
pub struct Installed {
    pub flavour: Flavour,
    pub name: String,
    pub path: PathBuf,
    pub target: &'static str,
}

/// The downloaded GE-Proton and Proton-CachyOS folders in the targets
/// (never the system's or Valve's).
pub fn installed(targets: &[Target]) -> Vec<Installed> {
    let mut list = Vec::new();
    for t in targets {
        let Ok(entries) = std::fs::read_dir(&t.dir) else { continue };
        let mut found: Vec<(String, PathBuf)> = entries
            .flatten()
            .filter(|e| e.file_type().is_ok_and(|f| f.is_dir()))
            .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path()))
            .collect();
        found.sort();
        for (name, path) in found {
            if let Some(flavour) = Flavour::ALL.into_iter().find(|f| f.owns(&name)) {
                let path = path.canonicalize().unwrap_or(path);
                list.push(Installed { flavour, name, path, target: t.id });
            }
        }
    }
    list
}

/// Whether `path` is a downloaded Proton folder the app may remove: a
/// real folder (no link) directly in a target, named like a download.
pub fn removable(targets: &[Target], path: &Path) -> bool {
    let Ok(meta) = std::fs::symlink_metadata(path) else { return false };
    if !meta.is_dir() {
        return false;
    }
    let Some(name) = path.file_name().and_then(|n| n.to_str()) else { return false };
    if !Flavour::ALL.iter().any(|f| f.owns(name)) {
        return false;
    }
    let Some(parent) = path.parent().and_then(|p| p.canonicalize().ok()) else { return false };
    targets.iter().any(|t| t.dir.canonicalize().is_ok_and(|d| d == parent))
}

/// Removes half-done downloads and unpacked folders (after a crash, or
/// when a job was ended).
pub fn tidy_leftovers(targets: &[Target]) {
    for t in targets {
        let Ok(entries) = std::fs::read_dir(&t.dir) else { continue };
        for e in entries.flatten() {
            if e.file_name().to_string_lossy().starts_with(PARTIAL) {
                let _ = std::fs::remove_dir_all(e.path());
            }
        }
    }
}

/// Removes half-done downloads.
pub fn tidy_downloads() {
    let _ = std::fs::remove_dir_all(download_dir());
}

pub fn download_dir() -> PathBuf {
    crate::updater::cache_dir().join("proton")
}

// ------------------------------------------------------------ pacman ----

/// proton-cachyos from pacman: what is installed and what the package
/// list on disk has (no network).
pub fn pacman_notes() -> Vec<Value> {
    let mut out = Vec::new();
    for pkg in ["proton-cachyos", "proton-cachyos-slr"] {
        let Some(have) = run_text(Command::new("pacman").args(["-Q", pkg])).and_then(|t| t.split_whitespace().nth(1).map(str::to_string)) else {
            continue;
        };
        let repo = run_text(Command::new("pacman").args(["-Si", pkg])).and_then(|t| {
            t.lines().find_map(|l| l.strip_prefix("Version").and_then(|r| r.split_once(':')).map(|(_, v)| v.trim().to_string()))
        });
        let newer = repo.as_ref().is_some_and(|r| {
            run_text(Command::new("vercmp").args([r.as_str(), have.as_str()])).and_then(|t| t.trim().parse::<i32>().ok()).is_some_and(|n| n > 0)
        });
        out.push(json!({"pkg": pkg, "have": have, "repo": repo.unwrap_or_default(), "newer": newer}));
    }
    out
}

fn run_text(command: &mut Command) -> Option<String> {
    let out = command.stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

// -------------------------------------------------------------- curl ----

fn curl() -> Command {
    let mut c = Command::new("curl");
    // -q: no curlrc; nothing but these flags decides where it goes.
    c.args(["-q", "--fail", "--silent", "--show-error", "--proto", "=https", "--max-redirs", "0"]);
    c.stdin(Stdio::null());
    c
}

/// Fetches the release list of a flavour (small, waited for).
pub fn fetch_releases(flavour: Flavour) -> Result<Vec<Release>, String> {
    if let Some(dir) = std::env::var_os("GC_PROTON_FAKE") {
        let text = std::fs::read_to_string(PathBuf::from(dir).join(format!("{}.json", flavour.id()))).map_err(|e| e.to_string())?;
        return parse_releases(flavour, &text);
    }
    let out = curl()
        .args(["--max-time", "30", "--max-filesize", "4194304", "-H", "Accept: application/vnd.github+json", "--", &flavour.api_url()])
        .output()
        .map_err(|e| format!("curl did not start: {e}"))?;
    let text = String::from_utf8_lossy(&out.stdout);
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        crate::log::write("proton", &format!("{}: release list failed ({})", flavour.id(), err.trim()));
        return Err(if err.contains("403") || err.contains("429") { "GitHub asks to wait (too many looks in an hour)".into() } else { "GitHub couldn't be reached".into() });
    }
    parse_releases(flavour, &text)
}

/// Where GitHub sends a release file (asked without following it).
fn resolve(flavour: Flavour, url: &str) -> Result<String, String> {
    if !download_ok(flavour, url) {
        return Err("The release points somewhere else".into());
    }
    let out = curl()
        .args(["--max-time", "30", "--output", "/dev/null", "--write-out", "%{http_code} %{redirect_url}", "--", url])
        .output()
        .map_err(|e| format!("curl did not start: {e}"))?;
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    let (code, target) = text.split_once(' ').unwrap_or((&text, ""));
    if code.starts_with('3') && redirect_ok(target.trim()) {
        Ok(target.trim().to_string())
    } else if code.starts_with('3') {
        Err("GitHub sent the download somewhere unexpected".into())
    } else {
        Err(format!("GitHub didn't give the file (HTTP {code})"))
    }
}

// --------------------------------------------------------------- job ----

/// What a running job tells the panel.
#[derive(Debug, Clone, PartialEq)]
pub enum Step {
    Download { done: u64, total: u64 },
    Check,
    Unpack,
}

/// Downloads, checks and unpacks one release into `target`. Returns the
/// installed folder's name. Stops when cancelled; leaves nothing behind
/// on failure.
pub fn install(flavour: Flavour, release: &Release, target: &Target, v3: bool, step: &mut dyn FnMut(Step)) -> Result<String, String> {
    CANCEL.store(false, Ordering::SeqCst);
    let (asset, sum) = pick_asset(flavour, release, v3).ok_or("This release has no file for this computer")?;
    let dir = download_dir();
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let file = dir.join(&asset.name);
    let partial = target.dir.join(format!("{PARTIAL}{}", release.tag));
    let result = (|| {
        // The checksum first: without one nothing is unpacked.
        let expected = match (&sum, &asset.digest) {
            (Some(sum), _) => {
                let url = resolve(flavour, &sum.url)?;
                let out = curl()
                    .args(["--max-time", "30", "--max-filesize", "65536", "--", &url])
                    .output()
                    .map_err(|e| format!("curl did not start: {e}"))?;
                if !out.status.success() {
                    return Err("The checksum couldn't be fetched".to_string());
                }
                ("sha512", sha512_from(&String::from_utf8_lossy(&out.stdout), &asset.name).ok_or("The checksum file names another file")?)
            }
            (None, Some(d)) if d.starts_with("sha256:") => ("sha256", d["sha256:".len()..].to_ascii_lowercase()),
            _ => return Err("The release has no checksum".to_string()),
        };
        let url = resolve(flavour, &asset.url)?;
        let cap = if asset.size > 0 { asset.size + 1024 * 1024 } else { 3 << 30 };
        let mut child = curl();
        child
            .args(["--max-time", "3600", "--speed-limit", "1024", "--speed-time", "60", "--max-filesize", &cap.to_string(), "--output"])
            .arg(&file)
            .arg("--")
            .arg(&url)
            .stdout(Stdio::null())
            .stderr(Stdio::piped());
        let started = Instant::now();
        run_child(&mut child, &mut || step(Step::Download { done: std::fs::metadata(&file).map(|m| m.len()).unwrap_or(0), total: asset.size }))
            .map_err(|e| if e.is_empty() { "The download failed".to_string() } else { format!("The download failed: {e}") })?;
        let size = std::fs::metadata(&file).map(|m| m.len()).unwrap_or(0);
        if asset.size > 0 && size != asset.size {
            return Err("The download is incomplete".into());
        }
        crate::log::write("proton", &format!("{}: downloaded {} ({} MB in {} s)", flavour.id(), asset.name, size >> 20, started.elapsed().as_secs()));
        step(Step::Check);
        let got = hash_file(&file, expected.0)?;
        if got != expected.1 {
            return Err("The download is damaged (wrong checksum)".into());
        }
        crate::log::write("proton", &format!("{}: {} checksum ok", flavour.id(), expected.0));
        step(Step::Unpack);
        unpack(flavour, &file, &asset.name, &target.dir, &partial)
    })();
    let _ = std::fs::remove_dir_all(&partial);
    let _ = std::fs::remove_file(&file);
    match &result {
        Ok(name) => {
            TOOLS_STALE.store(true, Ordering::SeqCst);
            crate::log::write("proton", &format!("{}: installed {name} for {}", flavour.id(), target.id));
        }
        Err(why) => crate::log::write("proton", &format!("{}: {} not installed: {why}", flavour.id(), release.tag)),
    }
    result
}

/// Unpacks `file` into a hidden folder beside the target's builds and
/// moves its one Proton folder into `dir` (named as the archive when its
/// own name isn't a download's). The hidden folder is the caller's to
/// remove.
fn unpack(flavour: Flavour, file: &Path, archive: &str, dir: &Path, partial: &Path) -> Result<String, String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let _ = std::fs::remove_dir_all(partial);
    std::fs::create_dir(partial).map_err(|e| e.to_string())?;
    let mut tar = Command::new("tar");
    tar.arg("-xf")
        .arg(file)
        .arg("-C")
        .arg(partial)
        .args(["--no-same-owner", "--no-same-permissions"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    run_child(&mut tar, &mut || {}).map_err(|e| if e.is_empty() { "Unpacking failed".to_string() } else { format!("Unpacking failed: {e}") })?;
    let tops: Vec<PathBuf> = std::fs::read_dir(partial).map_err(|e| e.to_string())?.flatten().map(|e| e.path()).collect();
    let [top] = tops.as_slice() else { return Err("The archive doesn't hold one Proton folder".into()) };
    let mut name = top.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
    if !top.join("proton").is_file() {
        return Err("The archive doesn't hold a Proton folder".into());
    }
    // A folder named otherwise takes the archive's name, so the list
    // knows it as a download.
    if !safe_tag(&name) || !flavour.owns(&name) {
        name = archive.split(".tar.").next().unwrap_or("").to_string();
        if !safe_tag(&name) || !flavour.owns(&name) {
            return Err("The archive doesn't hold a Proton folder".into());
        }
    }
    let goal = dir.join(&name);
    if goal.exists() {
        return Err(format!("{name} is installed already"));
    }
    std::fs::rename(top, &goal).map_err(|e| e.to_string())?;
    Ok(name)
}

/// Runs a child to its end, telling `tick` every 250 ms; ends it when the
/// job is cancelled. The child dies with this thread's process.
fn run_child(command: &mut Command, tick: &mut dyn FnMut()) -> Result<(), String> {
    use std::os::unix::process::CommandExt;
    if CANCEL.load(Ordering::SeqCst) {
        return Err("Stopped".into());
    }
    // SAFETY: only prctl in the child before exec.
    unsafe {
        command.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL);
            Ok(())
        });
    }
    let mut child: Child = command.spawn().map_err(|e| e.to_string())?;
    CHILD.store(child.id() as i32, Ordering::SeqCst);
    let mut stderr = child.stderr.take();
    let status = loop {
        if CANCEL.load(Ordering::SeqCst) {
            let _ = child.kill();
            let _ = child.wait();
            CHILD.store(0, Ordering::SeqCst);
            return Err("Stopped".into());
        }
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(e) => return Err(e.to_string()),
        }
        tick();
        std::thread::sleep(Duration::from_millis(250));
    };
    CHILD.store(0, Ordering::SeqCst);
    if status.success() {
        return Ok(());
    }
    let mut text = String::new();
    if let Some(e) = stderr.as_mut() {
        let _ = e.take(2048).read_to_string(&mut text);
    }
    Err(crate::log::clean(text.lines().last().unwrap_or("").trim()))
}

fn hash_file(path: &Path, kind: &str) -> Result<String, String> {
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut buf = vec![0u8; 1 << 20];
    let mut sha256 = Sha256::new();
    let mut sha512 = Sha512::new();
    loop {
        if CANCEL.load(Ordering::SeqCst) {
            return Err("Stopped".into());
        }
        let n = file.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        if kind == "sha512" {
            sha512.update(&buf[..n]);
        } else {
            sha256.update(&buf[..n]);
        }
    }
    let bytes: Vec<u8> = if kind == "sha512" { sha512.finalize().to_vec() } else { sha256.finalize().to_vec() };
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// Asks a running job to stop.
pub fn cancel() {
    CANCEL.store(true, Ordering::SeqCst);
}

/// The app quits: a running curl or tar ends at once, and what it left
/// is removed.
pub fn stop() {
    CANCEL.store(true, Ordering::SeqCst);
    let pid = CHILD.swap(0, Ordering::SeqCst);
    if pid > 0 {
        // SAFETY: a signal to our own child.
        unsafe { libc::kill(pid, libc::SIGKILL) };
        crate::log::write("proton", "a download was running: ended");
    }
    if RAN.load(Ordering::SeqCst) {
        if let Some(home) = std::env::var_os("HOME") {
            tidy_leftovers(&targets(Path::new(&home)));
        }
        tidy_downloads();
    }
}

/// Whether a job ran in this session (only then `stop` looks for leftovers).
pub static RAN: AtomicBool = AtomicBool::new(false);

// ------------------------------------------------------------- cache ----

/// The release lists kept between looks (and over a restart, in
/// ~/.cache/game-companion/proton-releases.json).
pub struct Kept {
    pub at: u64,
    pub lists: Vec<(Flavour, Vec<Release>)>,
}

pub static KEPT: Mutex<Option<Kept>> = Mutex::new(None);

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn release_json(r: &Release) -> Value {
    json!({
        "tag": r.tag, "name": r.name, "published": r.published, "body": r.body, "page": r.page,
        "assets": r.assets.iter().map(|a| json!({"name": a.name, "url": a.url, "size": a.size, "digest": a.digest})).collect::<Vec<_>>(),
    })
}

fn release_from(flavour: Flavour, v: &Value) -> Option<Release> {
    let s = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let tag = s("tag");
    if !safe_tag(&tag) {
        return None;
    }
    let assets = v
        .get("assets")
        .and_then(Value::as_array)?
        .iter()
        .filter_map(|a| {
            let url = a.get("url")?.as_str()?.to_string();
            download_ok(flavour, &url).then(|| Asset {
                name: a.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
                url,
                size: a.get("size").and_then(Value::as_u64).unwrap_or(0),
                digest: a.get("digest").and_then(Value::as_str).map(str::to_string),
            })
        })
        .collect();
    let page = s("page");
    Some(Release { tag, name: s("name"), published: s("published"), body: s("body"), page: if release_page_ok(&page) { page } else { String::new() }, assets })
}

fn cache_file() -> PathBuf {
    crate::updater::cache_dir().join("proton-releases.json")
}

pub fn save_kept(kept: &Kept) {
    let lists: serde_json::Map<String, Value> =
        kept.lists.iter().map(|(f, l)| (f.id().to_string(), Value::Array(l.iter().map(release_json).collect()))).collect();
    let _ = std::fs::create_dir_all(crate::updater::cache_dir());
    let _ = std::fs::write(cache_file(), json!({"at": kept.at, "lists": lists}).to_string());
}

pub fn load_kept() -> Option<Kept> {
    let v: Value = serde_json::from_str(&std::fs::read_to_string(cache_file()).ok()?).ok()?;
    let at = v.get("at")?.as_u64()?;
    let lists = Flavour::ALL
        .into_iter()
        .filter_map(|f| {
            let list = v.get("lists")?.get(f.id())?.as_array()?;
            Some((f, list.iter().filter_map(|r| release_from(f, r)).collect()))
        })
        .collect();
    Some(Kept { at, lists })
}

/// Opens a release's page in the desktop's browser (only on a click).
pub fn open_page(url: &str) -> Result<(), String> {
    if !release_page_ok(url) {
        return Err("not a release page".into());
    }
    let mut child = Command::new("xdg-open")
        .arg(url)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("xdg-open: {e}"))?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn release(flavour: Flavour, tag: &str, files: &[&str]) -> String {
        let assets: Vec<Value> = files
            .iter()
            .map(|f| json!({"name": f, "size": 10, "browser_download_url": format!("https://github.com/{}/releases/download/{tag}/{f}", flavour.repo())}))
            .collect();
        json!({"tag_name": tag, "name": tag, "draft": false, "prerelease": false, "published_at": "2026-11-03T07:19:00Z",
            "html_url": format!("https://github.com/{}/releases/tag/{tag}", flavour.repo()), "body": "Fixes", "assets": assets})
        .to_string()
    }

    #[test]
    fn reads_releases_from_its_own_repository_only() {
        let text = format!(
            "[{}, {}]",
            release(Flavour::Ge, "GE-Proton11-12", &["GE-Proton11-12.tar.gz", "GE-Proton11-12.sha512sum"]),
            r#"{"tag_name":"x","draft":true,"assets":[]}"#
        );
        let list = parse_releases(Flavour::Ge, &text).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].assets.len(), 2);
        assert!(release_page_ok(&list[0].page));
        // Another repository's files are dropped.
        let other = release(Flavour::Cachy, "GE-Proton11-12", &["GE-Proton11-12.tar.gz"]);
        assert!(parse_releases(Flavour::Ge, &format!("[{other}]")).unwrap()[0].assets.is_empty());
        assert!(parse_releases(Flavour::Ge, r#"{"message":"API rate limit exceeded"}"#).unwrap_err().contains("wait"));
    }

    #[test]
    fn addresses() {
        assert!(download_ok(Flavour::Ge, "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-12/GE-Proton11-12.tar.gz"));
        assert!(!download_ok(Flavour::Ge, "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/../x/y"));
        assert!(!download_ok(Flavour::Ge, "https://github.com/someone/proton-ge-custom/releases/download/a/b.tar.gz"));
        assert!(!download_ok(Flavour::Cachy, "https://github.com/CachyOS/proton-cachyos/releases/download/a/b/c"));
        assert!(redirect_ok("https://release-assets.githubusercontent.com/github-production-release-asset/1?x=y&z=1"));
        assert!(redirect_ok("https://objects.githubusercontent.com/a"));
        assert!(!redirect_ok("https://example.com/a"));
        assert!(!redirect_ok("http://objects.githubusercontent.com/a"));
        assert!(release_page_ok("https://github.com/CachyOS/proton-cachyos/releases/tag/cachyos-11.0-20261015-slr"));
        assert!(!release_page_ok("https://github.com/CachyOS/proton-cachyos/releases/tag/a b"));
        assert!(!release_page_ok("https://github.com/CachyOS/other/releases/tag/x"));
    }

    #[test]
    fn picks_the_file_for_this_cpu() {
        let text = format!(
            "[{}]",
            release(
                Flavour::Cachy,
                "cachyos-11.0-20261015-slr",
                &[
                    "proton-cachyos-11.0-20261015-slr-x86_64.tar.xz",
                    "proton-cachyos-11.0-20261015-slr-x86_64.sha512sum",
                    "proton-cachyos-11.0-20261015-slr-x86_64_v3.tar.xz",
                    "proton-cachyos-11.0-20261015-slr-x86_64_v3.sha512sum",
                ]
            )
        );
        let r = &parse_releases(Flavour::Cachy, &text).unwrap()[0];
        let (a, s) = pick_asset(Flavour::Cachy, r, true).unwrap();
        assert_eq!(a.name, "proton-cachyos-11.0-20261015-slr-x86_64_v3.tar.xz");
        assert_eq!(s.unwrap().name, "proton-cachyos-11.0-20261015-slr-x86_64_v3.sha512sum");
        let (a, s) = pick_asset(Flavour::Cachy, r, false).unwrap();
        assert_eq!(a.name, "proton-cachyos-11.0-20261015-slr-x86_64.tar.xz");
        assert_eq!(s.unwrap().name, "proton-cachyos-11.0-20261015-slr-x86_64.sha512sum");
        let ge = format!("[{}]", release(Flavour::Ge, "GE-Proton11-12", &["GE-Proton11-12.tar.gz", "GE-Proton11-12.sha512sum"]));
        let r = &parse_releases(Flavour::Ge, &ge).unwrap()[0];
        let (a, s) = pick_asset(Flavour::Ge, r, true).unwrap();
        assert_eq!((a.name.as_str(), s.unwrap().name.as_str()), ("GE-Proton11-12.tar.gz", "GE-Proton11-12.sha512sum"));
        assert!(cpu_v3("flags\t\t: fpu sse avx avx2 bmi1 bmi2 fma movbe f16c abm\n"));
        assert!(!cpu_v3("flags\t\t: fpu sse avx\n"));
    }

    #[test]
    fn checksum_lines() {
        let h = "a".repeat(128);
        assert_eq!(sha512_from(&format!("{h}  GE-Proton11-12.tar.gz\n"), "GE-Proton11-12.tar.gz").as_deref(), Some(h.as_str()));
        assert_eq!(sha512_from(&format!("{h} *./x.tar.xz\n"), "x.tar.xz").as_deref(), Some(h.as_str()));
        assert_eq!(sha512_from(&format!("{h}\n"), "x.tar.xz").as_deref(), Some(h.as_str()));
        assert_eq!(sha512_from(&format!("{h}  a\n{h}  b\n"), "c"), None);
        assert_eq!(sha512_from("short  x", "x"), None);
    }

    #[test]
    fn versions() {
        assert_eq!(version_key(Flavour::Ge, "GE-Proton10-25"), Some((10, 25, 0)));
        assert!(version_key(Flavour::Ge, "GE-Proton11-2") > version_key(Flavour::Ge, "GE-Proton10-25"));
        assert_eq!(version_key(Flavour::Cachy, "cachyos-11.0-20261015-slr"), Some((11, 0, 20261015)));
        assert_eq!(version_key(Flavour::Cachy, "proton-cachyos-11.0-20261015-slr-x86_64_v3"), Some((11, 0, 20261015)));
        assert!(Flavour::Cachy.owns("proton-cachyos-11.0-20261015-slr-x86_64"));
        assert!(!Flavour::Cachy.owns("proton-cachyos"), "the pacman package's folder is not a download");
    }

    #[test]
    fn notes_and_mentions() {
        let body = "## Changes\n- **Fixed** [Elden Ring](https://x) stutter\n- Added AION 2 fix\n\n\n- `dxvk` 2.5";
        let text = notes_text(body, 500);
        assert_eq!(text, "Changes\n• Fixed Elden Ring stutter\n• Added AION 2 fix\n\n• dxvk 2.5");
        assert!(notes_text(&"x".repeat(900), 100).ends_with('…'));
        let games = vec!["Elden Ring".to_string(), "AION 2".to_string(), "Ring".to_string(), "Fix".to_string()];
        assert_eq!(mentions(body, &games), vec!["Elden Ring".to_string(), "AION 2".to_string(), "Ring".to_string()]);
        assert!(mentions("aion 20", &["AION 2".to_string()]).is_empty());
    }

    #[test]
    fn installs_and_cleans_up() {
        let root = std::env::temp_dir().join(format!("gc-proton-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let steam = root.join("compat");
        std::fs::create_dir_all(steam.join("GE-Proton9-20")).unwrap();
        std::fs::create_dir_all(steam.join("my-proton")).unwrap();
        std::fs::create_dir_all(steam.join(format!("{PARTIAL}GE-Proton11-1"))).unwrap();
        let targets = vec![Target { id: "steam", label: "Steam", dir: steam.clone() }];
        let list = installed(&targets);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "GE-Proton9-20");
        assert!(removable(&targets, &steam.join("GE-Proton9-20")));
        assert!(!removable(&targets, &steam.join("my-proton")));
        assert!(!removable(&targets, &root.join("GE-Proton9-20")));
        std::os::unix::fs::symlink(steam.join("GE-Proton9-20"), steam.join("GE-Proton9-21")).unwrap();
        assert!(!removable(&targets, &steam.join("GE-Proton9-21")), "a link is not removed");
        tidy_leftovers(&targets);
        assert!(!steam.join(format!("{PARTIAL}GE-Proton11-1")).exists());
        assert!(steam.join("GE-Proton9-20").exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn unpacks_one_proton_folder() {
        let root = std::env::temp_dir().join(format!("gc-unpack-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let src = root.join("src/GE-Proton11-12");
        std::fs::create_dir_all(src.join("files")).unwrap();
        std::fs::write(src.join("proton"), "#!/bin/sh").unwrap();
        std::fs::write(src.join("compatibilitytool.vdf"), "x").unwrap();
        let file = root.join("GE-Proton11-12.tar.gz");
        assert!(Command::new("tar").arg("-czf").arg(&file).arg("-C").arg(root.join("src")).arg("GE-Proton11-12").status().unwrap().success());
        let dir = root.join("compat");
        let partial = dir.join(format!("{PARTIAL}GE-Proton11-12"));
        CANCEL.store(false, Ordering::SeqCst);
        assert_eq!(unpack(Flavour::Ge, &file, "GE-Proton11-12.tar.gz", &dir, &partial).unwrap(), "GE-Proton11-12");
        assert!(dir.join("GE-Proton11-12/proton").is_file());
        assert!(unpack(Flavour::Ge, &file, "GE-Proton11-12.tar.gz", &dir, &partial).unwrap_err().contains("installed already"));
        // A folder named otherwise takes the archive's name.
        std::fs::rename(&src, root.join("src/proton")).unwrap();
        let cachy = root.join("c.tar.xz");
        assert!(Command::new("tar").arg("-cJf").arg(&cachy).arg("-C").arg(root.join("src")).arg("proton").status().unwrap().success());
        let name = "proton-cachyos-11.0-20261015-slr-x86_64_v3.tar.xz";
        assert_eq!(unpack(Flavour::Cachy, &cachy, name, &dir, &partial).unwrap(), "proton-cachyos-11.0-20261015-slr-x86_64_v3");
        let _ = std::fs::remove_dir_all(&root);
    }
}
