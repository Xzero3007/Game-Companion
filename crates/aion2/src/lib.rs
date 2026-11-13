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
