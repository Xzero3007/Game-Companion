//! Game Companion: one overlay for every game on Linux (KDE Plasma, Wayland).

mod companion;
mod native;
mod radio;
mod radio_object;
mod settings;
mod shortcuts;

fn main() {
    if std::env::args().any(|a| a == "--version") {
        println!("Game Companion {}", companion::version_text());
        return;
    }
    cxx_qt::init_crate!(game_companion);
    cxx_qt::init_qml_module!("GameCompanion");
    std::process::exit(native::run());
}
