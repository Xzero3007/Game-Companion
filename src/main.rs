//! Game Companion: one overlay for every game on Linux (KDE Plasma, Wayland).

mod aion2_object;
mod companion;
mod emotes;
mod games;
mod games_object;
mod instance;
mod jellyfin;
mod jellyfin_object;
mod library;
mod library_object;
mod launch_check;
mod launch_demo;
mod launch_options;
mod native;
mod protondb;
mod radio;
mod radio_object;
mod settings;
mod shortcuts;
mod sponsorblock;
mod streams;
mod streams_object;
mod tray;
mod system_info;
mod updater;
mod updates_object;
mod vdf_edit;

fn main() {
    if std::env::args().any(|a| a == "--version") {
        println!("Game Companion {}", companion::version_text());
        return;
    }
    // One Game Companion at a time: a second start brings the running one
    // forward (unless it was started hidden, as with the desktop) and ends.
    let dir = instance::runtime_dir();
    let Some(_lock) = instance::lock(&dir) else {
        if std::env::args().any(|a| a == "--hidden") {
            return;
        }
        if !instance::ask_to_show(&dir) {
            eprintln!("Game Companion is already running.");
        }
        return;
    };
    if let Some(listener) = instance::bind(&dir) {
        instance::keep(listener);
    }
    cxx_qt::init_crate!(game_companion);
    cxx_qt::init_qml_module!("GameCompanion");
    let code = native::run();
    // Where the last video stopped, if not yet written.
    library::save_now();
    std::process::exit(code);
}
