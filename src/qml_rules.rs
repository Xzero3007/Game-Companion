//! Rules the QML must keep (tests only), checked on its source: each one broke once
//! in MN's use and is cheap to guard here (MN, 2026-11-25: "wieso geht
//! hier ständig was kaputt").

use std::fs;

fn qml(path: &str) -> String {
    fs::read_to_string(format!("{}/qml/{path}", env!("CARGO_MANIFEST_DIR"))).expect(path)
}

/// The text of each `GameButton { … }` block in the game row.
fn game_buttons(src: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = src;
    while let Some(at) = rest.find("GameButton {") {
        let body = &rest[at..];
        let mut depth = 0;
        let mut end = body.len();
        for (i, c) in body.char_indices() {
            match c {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = i + 1;
                        break;
                    }
                }
                _ => {}
            }
        }
        out.push(body[..end].to_string());
        rest = &body[end..];
    }
    out
}

/// A game button whose right-click switches something on shows that it is
/// on (a gold dot, `marked`). Loot's farm window had none (2026-11-25).
#[test]
fn right_click_toggles_show_their_state() {
    let buttons = game_buttons(&qml("GameRow.qml"));
    assert!(buttons.len() >= 8, "game buttons not found");
    for b in buttons.iter().filter(|b| b.contains("onRightClicked")) {
        assert!(b.contains("marked:"), "a GameButton with a right-click has no `marked`:\n{b}");
    }
    let main = qml("Main.qml");
    for bound in ["farmOn:", "sessionWindowOn:", "overlayOn:"] {
        assert!(main.contains(bound), "Main.qml doesn't bind {bound}");
    }
}

/// A see-through video is drawn by Qt, not on the HDR surface: the
/// surface's alpha modifier left it solid on MN's KWin (0.8.75 to 0.8.85).
#[test]
fn see_through_video_is_not_on_the_hdr_surface() {
    let src = qml("VideoWindow.qml");
    let line = src
        .lines()
        .find(|l| l.trim_start().starts_with("hdr:"))
        .expect("MpvVideo's hdr binding");
    assert!(line.contains("win.videoOpacity >= 0.995"), "HDR must need full opacity: {line}");
}
