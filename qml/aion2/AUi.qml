import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme

// The Armory's small parts, shared by its tabs (AUi.Line, AUi.Head, ...).
QtObject {
    /// Body text.
    component Line: Text {
        color: Theme.text()
        font.family: Theme.body
        font.pixelSize: 12
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// Text that wraps (notes, explanations).
    component Note: Text {
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A column's or box's head in capitals.
    component Head: Text {
        color: Theme.dim()
        font.family: Theme.display
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A section's title (13 px capitals, white).
    component Title: Text {
        color: Theme.text()
        font.family: Theme.display
        font.pixelSize: 13
        font.weight: Font.Bold
        font.letterSpacing: 1.5
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A number in the display font.
    component Figure: Text {
        color: Theme.text()
        font.family: Theme.display
        font.pixelSize: 15
        font.weight: Font.Bold
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A thin bar: `value` 0..1 in the accent, `mark` (0..1, -1 none) a
    /// white tick (the build's), `second` a fainter second bar.
    component Bar: Item {
        property real value: 0
        property real second: -1
        property real mark: -1
        property color colour: Theme.accent
        height: 5
        Rectangle { anchors.fill: parent; color: Theme.trackDark }
        Rectangle { visible: parent.second >= 0; width: parent.width * Math.max(0, Math.min(1, parent.second)); height: parent.height; color: Qt.rgba(1, 1, 1, 0.25) }
        Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.value)); height: parent.height; color: parent.colour }
        Rectangle { visible: parent.mark >= 0; x: parent.width * Math.max(0, Math.min(1, parent.mark)) - 1; y: -2; width: 2; height: parent.height + 4; color: "#ffffff" }
    }
    /// A dark box round a part of a tab.
    component Box: Rectangle {
        color: "#1b1a20"
        default property alias inner: col.data
        property alias spacing: col.spacing
        property int pad: 10
        implicitHeight: col.implicitHeight + 2 * pad
        Column {
            id: col
            x: parent.pad
            y: parent.pad
            width: parent.width - 2 * parent.pad
            spacing: 6
        }
    }
    /// A game icon (the Market's icon cache) with its grade's colour round it.
    component Icon: Rectangle {
        property string icon: ""
        property string grade: ""
        property int rev: 0
        width: 32
        height: 32
        color: "#121116"
        border.color: grade === "Unique" ? "#f2c46b" : grade === "Legend" ? "#4fa8ff" : grade === "Rare" ? "#7fdc9a" : grade === "Epic" ? "#c4a8f0" : "#3a3842"
        Image {
            anchors.fill: parent
            anchors.margins: 1
            asynchronous: true
            sourceSize.width: 64
            source: {
                parent.rev
                const s = String(parent.icon || "")
                const name = s.split(/[\/\\]/).pop().replace(/\.(webp|png|jpg)$/i, "")
                return name ? Aion2.icon(name) : ""
            }
        }
    }
    /// A small square tick box.
    component Tick: Item {
        property bool on: false
        property bool enabled: true
        signal toggled
        width: 16
        height: 16
        Rectangle {
            anchors.centerIn: parent
            width: 14
            height: 14
            color: parent.on ? Theme.accent : "transparent"
            border.color: parent.on ? Theme.accent : "#5a5862"
            opacity: parent.enabled ? 1 : 0.4
            Text { anchors.centerIn: parent; text: parent.parent.on ? "✓" : ""; color: "#0c0c0f"; font.pixelSize: 11; font.weight: Font.Bold }
        }
        MouseArea { anchors.fill: parent; enabled: parent.enabled; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
    }
    /// A text field in the panels' look.
    component Field: Rectangle {
        property alias text: input.text
        property string placeholder: ""
        property alias input: input
        signal edited(string text)
        signal accepted
        width: 140
        height: 24
        color: "#1b1a20"
        border.color: input.activeFocus ? Theme.accent : "#3a3842"
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text()
            selectionColor: Theme.accent
            font.family: Theme.body
            font.pixelSize: 12
            clip: true
            onTextEdited: parent.edited(text)
            onAccepted: parent.accepted()
            Keys.onEscapePressed: focus = false
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: input.parent.placeholder
                color: Theme.dim()
                font: input.font
            }
        }
    }
    /// − value + for a level (enhance, Amplify, a skill's target). No
    /// Repeater inside: Qt 6.4 crashed making one of these in a delegate.
    component StepButton: Item {
        property string sign: "+"
        signal hit
        width: 18
        height: 20
        Rectangle { anchors.fill: parent; color: sm.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"; border.color: "#3a3842" }
        Text { anchors.centerIn: parent; text: parent.sign; color: Theme.text(); font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold }
        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.hit() }
    }
    component Stepper: Row {
        id: st
        property int value: 0
        property int from: 0
        property int to: 15
        property string prefix: ""
        signal changed(int value)
        function step(d) { const v = Math.max(from, Math.min(to, value + d)); if (v !== value) changed(v) }
        spacing: 2
        StepButton { sign: "−"; onHit: st.step(-1) }
        Item {
            width: Math.max(26, val.implicitWidth + 6)
            height: 20
            Text { id: val; anchors.centerIn: parent; text: st.prefix + st.value; color: Theme.text(); font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold }
        }
        StepButton { sign: "+"; onHit: st.step(1) }
    }
    /// Enhance and Amplify levels for a piece (Amplify from the enhance top
    /// on, never below `min`); `kit` is the Armory's calc (AK.C).
    component LevelSet: Row {
        id: ls
        property var kit
        property var piece
        property var min: null
        signal picked(var lv)
        readonly property var t: kit ? kit.tops(piece) : ({ enchant: 15, amplify: 0 })
        readonly property int etop: t.enchant || 15
        spacing: 6
        Stepper {
            prefix: "+"
            value: ls.piece.enchant || 0
            from: ls.min ? ls.min.enchant || 0 : 0
            to: ls.etop
            onChanged: (v) => ls.picked({ enchant: v, amplify: v < ls.etop ? 0 : (ls.piece.amplify || 0) })
        }
        Stepper {
            visible: ls.t.amplify > 0
            opacity: (ls.piece.enchant || 0) >= ls.etop ? 1 : 0.4
            prefix: "A"
            value: ls.piece.amplify || 0
            from: ls.min ? ls.min.amplify || 0 : 0
            to: ls.t.amplify
            onChanged: (v) => ls.picked({ enchant: v > 0 ? ls.etop : (ls.piece.enchant || 0), amplify: v })
        }
    }
}
