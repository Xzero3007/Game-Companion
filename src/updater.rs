//! Updates from this project's own GitHub releases, and nothing else: the
//! release manifest (`latest.json`) and the Arch package it names. The user's
//! curl fetches them; the installed package's root script
//! (`/usr/lib/game-companion-update`, through pkexec without a password)
//! installs only the latest release, by the checksum it reads itself.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Deserialize;
use sha2::{Digest, Sha256};

pub const MANIFEST_URL: &str = "https://github.com/Xzero3007/Game-Companion/releases/latest/download/latest.json";
/// The beta channel's manifest: the rolling release `beta-channel`, which
/// the workflow points at the newest build of the `beta` branch.
pub const BETA_MANIFEST_URL: &str = "https://github.com/Xzero3007/Game-Companion/releases/download/beta-channel/latest.json";
/// Packages are downloaded from here only.
pub const DOWNLOAD_PREFIX: &str = "https://github.com/Xzero3007/Game-Companion/releases/download/";
const UPDATE_HELPER: &str = "/usr/lib/game-companion-update";
const INSTALLED_BINARY: &str = "/usr/bin/game-companion";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Release {
    pub version: String,
    pub build: u32,
    pub arch_url: String,
    pub arch_sha256: String,
}

impl Release {
    pub fn label(&self) -> String {
        format!("{} (build {})", self.version, self.build)
    }
}

/// This app's build number: the release workflow's run number, 0 for a
/// build made by hand.
pub fn current_build() -> u32 {
    option_env!("GC_BUILD").and_then(|b| b.parse().ok()).unwrap_or(0)
}

/// Whether this app was built from the `beta` branch (the workflow sets
/// GC_CHANNEL=beta there).
pub fn running_beta() -> bool {
    option_env!("GC_CHANNEL") == Some("beta")
}

/// Whether to offer the release: a newer build of the channel this app came
/// from, or, when the user picked the other channel, its build (older or
/// newer: going back to stable installs stable's latest).
pub fn should_offer(release: &Release, current_build: u32, running_beta: bool, wanted_beta: bool) -> bool {
    if running_beta == wanted_beta {
        is_newer(release, current_build)
    } else {
        release.build != current_build
    }
}

/// Reads and checks a release manifest.
pub fn parse_manifest(text: &str) -> Result<Release, String> {
    let release: Release = serde_json::from_str(text).map_err(|_| "The release list couldn't be read".to_string())?;
    if !release.arch_url.starts_with(DOWNLOAD_PREFIX) || release.arch_url.contains("..") {
        return Err("The release points somewhere else".into());
    }
    if release.arch_sha256.len() != 64 || !release.arch_sha256.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("The release has no checksum".into());
    }
    Ok(release)
}

/// Whether the release is newer than what runs.
pub fn is_newer(release: &Release, current_build: u32) -> bool {
    release.build > current_build
}

fn curl() -> Command {
    let mut c = Command::new("curl");
    c.args([
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "--max-redirs",
        "5",
    ]);
    c
}

/// The latest release of a channel, from GitHub.
pub fn fetch_latest(beta: bool) -> Result<Release, String> {
    let url = if beta { BETA_MANIFEST_URL } else { MANIFEST_URL };
    let out = curl()
        .args(["--max-time", "30", "--max-filesize", "65536", "--", url])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("curl did not start: {e}"))?;
    if !out.status.success() {
        return Err("GitHub couldn't be reached".into());
    }
    parse_manifest(&String::from_utf8_lossy(&out.stdout))
}

pub(crate) fn cache_dir() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
        .join("game-companion")
}

/// Downloads the release's package and checks its SHA-256.
pub fn download(release: &Release) -> Result<PathBuf, String> {
    let dir = cache_dir();
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let file = dir.join("game-companion-update.pkg.tar.zst");
    let status = curl()
        .args(["--max-time", "600", "--max-filesize", "268435456", "--output"])
        .arg(&file)
        .arg("--")
        .arg(&release.arch_url)
        .stdin(Stdio::null())
        .status()
        .map_err(|e| format!("curl did not start: {e}"))?;
    if !status.success() {
        let _ = std::fs::remove_file(&file);
        return Err("The download failed".into());
    }
    if sha256_of(&file)? != release.arch_sha256.to_ascii_lowercase() {
        let _ = std::fs::remove_file(&file);
        return Err("The download is damaged (wrong checksum)".into());
    }
    Ok(file)
}

pub fn sha256_of(path: &Path) -> Result<String, String> {
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 16];
    loop {
        let n = file.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// Whether this app is pacman's package (the update button installs only
/// then; a build made by hand is updated by building again).
pub fn installed_by_pacman() -> bool {
    std::env::current_exe().is_ok_and(|exe| exe == Path::new(INSTALLED_BINARY))
        && Command::new("pacman")
            .args(["-Qqo", INSTALLED_BINARY])
            .output()
            .is_ok_and(|o| o.status.success() && String::from_utf8_lossy(&o.stdout).trim() == "game-companion")
}

/// The script that waits for this app to close, installs the package
/// (without a password through the package's script; with it if that is
/// missing or refuses) and starts the app again. `$1` the package, `$2` this
/// app's pid, `$3` the log (what the root script says when it refuses).
pub fn installer_script(helper: bool) -> String {
    let fast = if helper { format!("/usr/bin/pkexec {UPDATE_HELPER} <\"$1\" || ") } else { String::new() };
    format!(
        r#"exec >>"$3" 2>&1
echo "$(date -Is) installing $1"
while kill -0 "$2" 2>/dev/null; do sleep 0.2; done
{fast}/usr/bin/pkexec /usr/bin/pacman -U --noconfirm -- "$1"
rm -f -- "$1"
exec {INSTALLED_BINARY}
"#
    )
}

/// Starts the installer, detached; the app must quit right after.
pub fn start_install(package: &Path) -> Result<(), String> {
    use std::os::unix::process::CommandExt;
    let helper = Path::new(UPDATE_HELPER).exists();
    let mut command = Command::new("/bin/sh");
    command
        .arg("-c")
        .arg(installer_script(helper))
        .arg("game-companion-install")
        .arg(package)
        .arg(std::process::id().to_string())
        .arg(cache_dir().join("update.log"))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // Its own session: it outlives the app.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    command.spawn().map(|_| ()).map_err(|e| format!("The installer did not start: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn manifest(url: &str, sha: &str) -> String {
        format!(r#"{{"version":"0.3.0","build":12,"archUrl":"{url}","archSha256":"{sha}"}}"#)
    }

    #[test]
    fn reads_a_release() {
        let r = parse_manifest(&manifest(
            "https://github.com/Xzero3007/Game-Companion/releases/download/v0.3.0-12/game-companion-0.3.0-1-x86_64.pkg.tar.zst",
            SHA,
        ))
        .unwrap();
        assert_eq!(r.build, 12);
        assert_eq!(r.label(), "0.3.0 (build 12)");
        assert!(is_newer(&r, 11));
        assert!(!is_newer(&r, 12));
        assert!(is_newer(&r, 0), "a build made by hand takes the release");
    }

    #[test]
    fn channels() {
        let r = parse_manifest(&manifest(
            "https://github.com/Xzero3007/Game-Companion/releases/download/v0.3.0-12/game-companion-0.3.0-1-x86_64.pkg.tar.zst",
            SHA,
        ))
        .unwrap();
        // Same channel: only newer builds.
        assert!(should_offer(&r, 11, false, false));
        assert!(!should_offer(&r, 12, true, true));
        assert!(!should_offer(&r, 20, false, false));
        // Back from beta (build 20) to stable (build 12): offered although older.
        assert!(should_offer(&r, 20, true, false));
        // Onto beta from stable.
        assert!(should_offer(&r, 5, false, true));
        assert!(!should_offer(&r, 12, false, true));
        assert!(BETA_MANIFEST_URL.starts_with(DOWNLOAD_PREFIX));
    }

    #[test]
    fn refuses_other_places_and_missing_checksums() {
        assert!(parse_manifest(&manifest("https://example.com/x.pkg.tar.zst", SHA)).is_err());
        assert!(parse_manifest(&manifest(
            "https://github.com/Xzero3007/Game-Companion/releases/download/../../other/x.pkg",
            SHA
        ))
        .is_err());
        assert!(parse_manifest(&manifest(
            "https://github.com/Xzero3007/Game-Companion/releases/download/v1/x.pkg.tar.zst",
            "nothex"
        ))
        .is_err());
        assert!(parse_manifest("{}").is_err());
    }

    #[test]
    fn the_script_without_password_goes_first() {
        let with = installer_script(true);
        let fast = with.find("/usr/bin/pkexec /usr/lib/game-companion-update <\"$1\" ||").unwrap();
        let prompt = with.find("/usr/bin/pkexec /usr/bin/pacman -U").unwrap();
        assert!(fast < prompt);
        // Nothing but the package on stdin: no argument the root script could trust.
        assert!(!with.contains("game-companion-update \""));
        assert!(!installer_script(false).contains(UPDATE_HELPER));
    }

    #[test]
    fn checksum_of_a_file() {
        let path = std::env::temp_dir().join(format!("gc-sha-{}", std::process::id()));
        std::fs::write(&path, b"abc").unwrap();
        assert_eq!(sha256_of(&path).unwrap(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        let _ = std::fs::remove_file(&path);
    }
}
