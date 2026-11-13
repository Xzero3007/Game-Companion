.pragma library

// Dragging and resizing a part: while the button is held, the part's
// window takes the whole screen and stays still (Surface.held), and the
// part moves inside it.
//
// Compositors differ in where they measure the pointer once that window
// has grown: KWin from the window's place now, Sway from its place at the
// press. The first move after the window took the screen tells which:
// whichever reading lies nearer to where the press was is right, the
// other is off by the window's old place (hundreds of pixels against a
// few of hand movement). Every later move gets the same correction.

function begin(w) {
    if (w && w.grab) w.grab(true)
}

function end(w) {
    if (w && w.grab) w.grab(false)
}

// Moves before the window took the screen are skipped.
function steady(w) {
    return !w || w.steady === undefined || w.steady
}

// `p` measured in screen coordinates (the part's parent), `start` the
// place of the press, `state` an object emptied at each press.
function fix(w, p, start, state) {
    if (!w || w.heldOrigin === undefined) return p
    if (state.corr === undefined) {
        const o = w.heldOrigin
        const alt = Qt.point(p.x + o.x, p.y + o.y)
        const far = (a) => Math.abs(a.x - start.x) + Math.abs(a.y - start.y)
        state.corr = far(alt) < far(p) ? o : Qt.point(0, 0)
    }
    return Qt.point(p.x + state.corr.x, p.y + state.corr.y)
}
