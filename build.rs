use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    let qml = QmlModule::new("GameCompanion").qml_files([
        QmlFile::from("qml/Main.qml"),
        QmlFile::from("qml/HudBar.qml"),
        QmlFile::from("qml/HudButton.qml"),
        QmlFile::from("qml/HudIcon.qml"),
        QmlFile::from("qml/Panel.qml"),
        QmlFile::from("qml/WelcomePanel.qml"),
        QmlFile::from("qml/SettingsPanel.qml"),
        QmlFile::from("qml/TextButton.qml"),
        QmlFile::from("qml/HudSlider.qml"),
        QmlFile::from("qml/IconButton.qml"),
        QmlFile::from("qml/VolumeBar.qml"),
        QmlFile::from("qml/Dropdown.qml"),
        QmlFile::from("qml/GamesPanel.qml"),
        QmlFile::from("qml/DpsPanel.qml"),
        QmlFile::from("qml/RadioPanel.qml"),
        QmlFile::from("qml/PlayerRow.qml"),
        QmlFile::from("qml/GameRow.qml"),
        QmlFile::from("qml/HubHint.qml"),
        QmlFile::from("qml/StreamsPanel.qml"),
        QmlFile::from("qml/VideoWindow.qml"),
        QmlFile::from("qml/Picker.qml"),
        QmlFile::from("qml/Chip.qml"),
        QmlFile::from("qml/ChatPanel.qml"),
        QmlFile::from("qml/WheelScroll.qml"),
        QmlFile::from("qml/JellyfinSignIn.qml"),
        QmlFile::from("qml/Surface.qml"),
        QmlFile::from("qml/MoveArea.qml"),
        QmlFile::from("qml/Overlay.qml"),
        QmlFile::from("qml/LaunchTab.qml"),
        QmlFile::from("qml/LaunchSuggestions.qml"),
        QmlFile::from("qml/ProtonOverview.qml"),
        QmlFile::from("qml/ChoiceList.qml"),
        QmlFile::from("qml/StatusMark.qml"),
        QmlFile::from("qml/Requests.qml"),
        QmlFile::from("qml/SelectBox.qml"),
        QmlFile::from("qml/Tag.qml"),
        QmlFile::from("qml/aion2/MapView.qml"),
        QmlFile::from("qml/aion2/MapOverlay.qml"),
        QmlFile::from("qml/aion2/MapPanel.qml"),
        QmlFile::from("qml/aion2/MarketPanel.qml"),
        QmlFile::from("qml/aion2/CharacterStore.qml"),
        QmlFile::from("qml/aion2/CharactersPanel.qml"),
        QmlFile::from("qml/aion2/TimerStore.qml"),
        QmlFile::from("qml/aion2/SchedulePanel.qml"),
        QmlFile::from("qml/aion2/AlertBanner.qml"),
    ]);

    let layer_shell = std::env::var_os("CARGO_FEATURE_LAYER_SHELL").is_some();
    if layer_shell {
        println!("cargo::rustc-link-lib=LayerShellQtInterface");
    }

    let builder = CxxQtBuilder::new_qml_module(qml)
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("OpenGL")
        .qt_module("Network")
        .qt_module("Svg")
        .files(["src/companion.rs", "src/radio_object.rs", "src/updates_object.rs", "src/streams_object.rs", "src/library_object.rs", "src/jellyfin_object.rs", "src/games_object.rs", "src/aion2_object.rs", "src/native.rs"])
        .cpp_file("cpp/native.h")
        .cpp_file("cpp/native.cpp")
        .cpp_file("cpp/mpvvideo.h")
        .cpp_file("cpp/mpvvideo.cpp")
        .cpp_file("cpp/icons.h")
        .cpp_file("cpp/icons.cpp")
        .cpp_file("cpp/twitchchat.h")
        .cpp_file("cpp/twitchchat.cpp")
        .cpp_file("cpp/jellyfinpictures.h")
        .cpp_file("cpp/jellyfinpictures.cpp")
        .qrc_resources([
            "assets/fonts/Rajdhani-Bold.ttf",
            "assets/fonts/Rajdhani-SemiBold.ttf",
            "assets/fonts/Inter.ttf",
            "assets/aion2/classes/assassin.png",
            "assets/aion2/classes/brawler.png",
            "assets/aion2/classes/chanter.png",
            "assets/aion2/classes/cleric.png",
            "assets/aion2/classes/gladiator.png",
            "assets/aion2/classes/ranger.png",
            "assets/aion2/classes/sorcerer.png",
            "assets/aion2/classes/spiritmaster.png",
            "assets/aion2/classes/templar.png",
            "assets/aion2/odyle.png",
            "qml/theme.js",
            "qml/drag.js",
            "qml/launch.js",
            "qml/plugins.js",
            "qml/aion2/mapkit.js",
            "qml/aion2/marketkit.js",
            "qml/aion2/charkit.js",
            "qml/aion2/chartickets.js",
            "qml/aion2/schedule.js",
            "qml/aion2/timekit.js",
        ]);
    // SAFETY: only adds include paths and a define to the C++ build.
    let builder = unsafe {
        builder.cc_builder(move |cc| {
            cc.include("cpp");
            if layer_shell {
                cc.define("GC_LAYER_SHELL", "1");
            }
        })
    };
    builder.build();
}
