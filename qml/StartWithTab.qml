import QtQuick
import GameCompanion
import "theme.js" as Theme

// The WITH GAME tab of a game's form (MN, 2026-11-14; the plan "Game
// Companion Launcher"): the programs that start with this game and close
// after it, and the starters other programs left in the desktop's autostart
// for it (the old meter's watcher). Every change here is saved at once.
Column {
    id: tab
    required property var game
    readonly property string gameId: game && game.id ? game.id : ""
    readonly property string gameName: game && game.name ? game.name : "this game"

    /// Games.startWith's answer.
    property var info: ({ entries: [], starters: [] })
    function reload() {
        try { info = JSON.parse(Games.startWith(gameId)) } catch (e) { info = { entries: [], starters: [] } }
    }
    Component.onCompleted: {
        reload()
        if (nativeWindow.demo.indexOf("addprogram") >= 0) { adding = true; picking = true }
    }

    /// The entry whose fields are open for editing (its id, or -1).
    property int editing: -1
    /// The add form is open, and its program list.
    property bool adding: false
    property bool picking: false
    property var programs: []
    /// A remove asks once more: which one ("entry:<id>", "starter:<file>",
    /// "all").
    property string confirming: ""
    property string error: ""

    /// Whether an entry already starts what a starter would.
    function hasEntryFor(command) {
        return (info.entries || []).some((e) => e.command.trim() === command)
    }

    spacing: 14

    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Game Companion is the watcher: it looks for your games every 3 s. When " + tab.gameName
            + " starts, the programs below start with it (not when they already run). When it ends, those set to close"
            + " end after their wait: asked first, ended hard 10 s later if still running. A program you started yourself"
            + " is never closed; one you close during the game comes back at its next start. Changes here apply at once."
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 12
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        visible: Companion.autostartMode === "off"
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Game Companion doesn't start when you log in (Settings → General → Start with the desktop): these programs start only while it runs."
        color: Theme.red
        font.family: Theme.body
        font.pixelSize: 12
    }

    // ---- What other programs start with this game (the old watcher) ----
    Repeater {
        model: tab.info.starters || []
        delegate: Rectangle {
            id: starterCard
            required property var modelData
            readonly property var s: modelData
            property bool showFile: nativeWindow.demo.indexOf("starterfile") >= 0
            readonly property bool doubled: s.on && tab.hasEntryFor(s.takeCommand)
            width: tab.width
            height: starterColumn.implicitHeight + 24
            color: "#16151b"
            border.color: doubled ? Theme.red : "#2e2c35"
            Column {
                id: starterColumn
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8
                Row {
                    spacing: 8
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        text: "ALREADY STARTS WITH " + tab.gameName.toUpperCase()
                        color: Theme.muted()
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    Tag { text: starterCard.s.on ? "ON" : "OFF"; tint: starterCard.s.on ? Theme.accent : "#5a5764"; size: 10 }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: starterCard.s.name
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: starterCard.s.about
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                    lineHeight: 1.15
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: starterCard.doubled
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Both would start the meter: turn the old watcher off."
                    color: Theme.red
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                // Its file, as it is on disk.
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: (starterCard.showFile ? "▾ " : "▸ ") + "FILE  " + starterCard.s.path
                    color: fileMouse.containsMouse ? Theme.accent : Theme.muted()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    MouseArea {
                        id: fileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: starterCard.showFile = !starterCard.showFile
                    }
                }
                Rectangle {
                    visible: starterCard.showFile
                    width: parent.width
                    height: fileText.implicitHeight + 16
                    color: "#0e0d12"
                    TextEdit {
                        id: fileText
                        x: 8
                        y: 8
                        width: parent.width - 16
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: starterCard.s.content
                        color: Theme.textSoft()
                        selectionColor: Theme.accent
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                }
                Row {
                    spacing: 10
                    visible: tab.confirming !== "starter:" + starterCard.s.file
                    TextButton {
                        visible: !tab.hasEntryFor(starterCard.s.takeCommand)
                        text: "Take over"
                        onClicked: {
                            tab.error = ""
                            if (!Games.addStartWith(tab.gameId, starterCard.s.takeName, starterCard.s.takeCommand, true, 10)) {
                                tab.error = "Couldn't add the meter."
                                return
                            }
                            if (starterCard.s.on && !Games.setStarter(starterCard.s.file, false)) tab.error = "Couldn't turn the old watcher off."
                            tab.reload()
                        }
                    }
                    TextButton {
                        text: starterCard.s.on ? "Turn off" : "Turn on"
                        onClicked: {
                            tab.error = Games.setStarter(starterCard.s.file, !starterCard.s.on) ? "" : "Couldn't move its file."
                            tab.reload()
                        }
                    }
                    TextButton { text: "Remove"; danger: true; onClicked: tab.confirming = "starter:" + starterCard.s.file }
                }
                Row {
                    spacing: 10
                    visible: tab.confirming === "starter:" + starterCard.s.file
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Delete its autostart file for good?"
                        color: Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                    }
                    TextButton {
                        text: "Remove"
                        danger: true
                        onClicked: {
                            tab.error = Games.removeStarter(starterCard.s.file) ? "" : "Couldn't delete its file."
                            tab.confirming = ""
                            tab.reload()
                        }
                    }
                    TextButton { text: "Keep"; onClicked: tab.confirming = "" }
                }
            }
        }
    }

    // ---- This game's programs ----
    Item {
        width: parent.width
        height: 20
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            anchors.verticalCenter: parent.verticalCenter
            text: "PROGRAMS THAT START WITH " + tab.gameName.toUpperCase()
            color: Theme.muted()
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        visible: (tab.info.entries || []).length === 0 && !tab.adding
        width: parent.width
        wrapMode: Text.WordWrap
        text: "None yet."
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 12
    }
    Repeater {
        model: tab.info.entries || []
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var e: modelData
            readonly property bool open: tab.editing === e.id
            width: tab.width
            height: rowColumn.implicitHeight + 20
            color: "#16151b"
            Column {
                id: rowColumn
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8
                Item {
                    width: parent.width
                    height: Math.max(36, nameColumn.implicitHeight)
                    Switch {
                        id: onSwitch
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        checked: row.e.on
                        onToggled: (on) => { Games.updateStartWith(tab.gameId, row.e.id, row.e.name, row.e.command, on, row.e.close, row.e.delay); tab.reload() }
                    }
                    Column {
                        id: nameColumn
                        anchors.left: onSwitch.right
                        anchors.leftMargin: 12
                        anchors.right: rowButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Row {
                            spacing: 8
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                text: row.e.name
                                color: row.e.on ? Theme.text() : Theme.dim()
                                font.family: Theme.body
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Tag { visible: row.e.running; text: "RUNNING"; tint: Theme.accent; size: 9; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.e.command
                            color: Theme.dim()
                            font.family: "monospace"
                            font.pixelSize: 11
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            text: row.e.close ? "Closes " + row.e.delay + " s after the game" : "Stays open after the game"
                            color: Theme.muted()
                            font.family: Theme.body
                            font.pixelSize: 11
                        }
                    }
                    Row {
                        id: rowButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        visible: tab.confirming !== "entry:" + row.e.id
                        TextButton { text: row.open ? "Done" : "Edit"; pixelSize: 12; pad: 10; onClicked: tab.editing = row.open ? -1 : row.e.id }
                        TextButton { text: "Remove"; danger: true; pixelSize: 12; pad: 10; onClicked: tab.confirming = "entry:" + row.e.id }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        visible: tab.confirming === "entry:" + row.e.id
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Remove it?"
                            color: Theme.text()
                            font.family: Theme.body
                            font.pixelSize: 13
                        }
                        TextButton {
                            text: "Remove"; danger: true; pixelSize: 12; pad: 10
                            onClicked: { Games.removeStartWith(tab.gameId, row.e.id); tab.confirming = ""; tab.editing = -1; tab.reload() }
                        }
                        TextButton { text: "Keep"; pixelSize: 12; pad: 10; onClicked: tab.confirming = "" }
                    }
                }
                // Its fields (Edit).
                Loader {
                    width: parent.width
                    active: row.open
                    visible: active
                    sourceComponent: EntryFields {
                        width: rowColumn.width
                        startName: row.e.name
                        startCommand: row.e.command
                        startClose: row.e.close
                        startDelay: row.e.delay
                        actionText: "Save"
                        onDone: (name, command, close, delay) => {
                            if (!Games.updateStartWith(tab.gameId, row.e.id, name, command, row.e.on, close, delay)) {
                                tab.error = "Couldn't save: check the command (a quote left open?)."
                                return
                            }
                            tab.error = ""
                            tab.editing = -1
                            tab.reload()
                        }
                    }
                }
            }
        }
    }

    // ---- Add ----
    Loader {
        width: parent.width
        active: tab.adding
        visible: active
        sourceComponent: Rectangle {
            width: tab.width
            height: addColumn.implicitHeight + 24
            color: "#16151b"
            border.color: "#2e2c35"
            Column {
                id: addColumn
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: "ADD A PROGRAM"
                    color: Theme.muted()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                // From the desktop's menu.
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: (tab.picking ? "▾ " : "▸ ") + "PICK FROM THE MENU"
                    color: pickMouse.containsMouse || tab.picking ? Theme.accent : Theme.muted()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    MouseArea {
                        id: pickMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tab.picking = !tab.picking
                    }
                }
                Column {
                    visible: tab.picking
                    width: parent.width
                    spacing: 6
                    Component.onCompleted: if (tab.programs.length === 0) { try { tab.programs = JSON.parse(Games.programs()) } catch (e) { } }
                    Field { id: filterField; width: parent.width; placeholder: "Filter" }
                    Rectangle {
                        width: parent.width
                        height: Math.min(180, programList.contentHeight + 2)
                        color: "#0e0d12"
                        clip: true
                        ListView {
                            id: programList
                            anchors.fill: parent
                            anchors.margins: 1
                            boundsBehavior: Flickable.StopAtBounds
                            model: tab.programs.filter((p) => filterField.text.length === 0
                                || p.name.toLowerCase().indexOf(filterField.text.toLowerCase()) >= 0)
                            delegate: Rectangle {
                                required property var modelData
                                width: programList.width
                                height: 28
                                color: itemMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
                                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.45
                                    elide: Text.ElideRight
                                    text: parent.modelData.name
                                    color: Theme.text()
                                    font.family: Theme.body
                                    font.pixelSize: 12
                                }
                                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                    x: parent.width * 0.45 + 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.55 - 24
                                    elide: Text.ElideRight
                                    text: parent.modelData.command
                                    color: Theme.dim()
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { addFields.setTo(parent.modelData.name, parent.modelData.command); tab.picking = false }
                                }
                            }
                        }
                        WheelScroll { flick: programList; step: 56 }
                    }
                }
                EntryFields {
                    id: addFields
                    width: parent.width
                    startDelay: 10
                    startClose: true
                    actionText: "Add"
                    showCancel: true
                    onCancelled: { tab.adding = false; tab.picking = false }
                    onDone: (name, command, close, delay) => {
                        if (!Games.addStartWith(tab.gameId, name, command, close, delay)) {
                            tab.error = "Couldn't add: check the command (a quote left open?)."
                            return
                        }
                        tab.error = ""
                        tab.adding = false
                        tab.picking = false
                        tab.reload()
                    }
                }
            }
        }
    }

    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        visible: tab.error.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: tab.error
        color: Theme.red
        font.family: Theme.body
        font.pixelSize: 12
    }

    Row {
        spacing: 10
        visible: !tab.adding
        TextButton { text: "+ Add program"; onClicked: { tab.adding = true; tab.editing = -1 } }
        TextButton {
            visible: (tab.info.entries || []).length > 1 && tab.confirming !== "all"
            text: "Remove all"
            danger: true
            onClicked: tab.confirming = "all"
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: tab.confirming === "all"
            anchors.verticalCenter: parent.verticalCenter
            text: "Remove every program of " + tab.gameName + "?"
            color: Theme.text()
            font.family: Theme.body
            font.pixelSize: 13
        }
        TextButton {
            visible: tab.confirming === "all"
            text: "Remove all"
            danger: true
            onClicked: { Games.clearStartWith(tab.gameId); tab.confirming = ""; tab.editing = -1; tab.reload() }
        }
        TextButton { visible: tab.confirming === "all"; text: "Keep"; onClicked: tab.confirming = "" }
    }

    // ---- Parts ----

    /// A program's fields: name, command, closes with the game, wait.
    component EntryFields: Column {
        id: fields
        property string startName: ""
        property string startCommand: ""
        property bool startClose: true
        property int startDelay: 10
        property string actionText: "Save"
        property bool showCancel: false
        signal done(string name, string command, bool close, int delay)
        signal cancelled()
        function setTo(name, command) { nameInput.text = name; commandInput.text = command }
        spacing: 10
        Component.onCompleted: {
            nameInput.text = startName
            commandInput.text = startCommand
            closeCheck.checked = startClose
            delayInput.text = String(startDelay)
        }
        Row {
            width: parent.width
            spacing: 10
            Column {
                width: (parent.width - 10) * 0.35
                spacing: 4
                Text { style: Theme.textStyle(); styleColor: Theme.shadow; text: "NAME"; color: Theme.dim(); font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5 }
                Field { id: nameInput; width: parent.width; placeholder: "e.g. Discord" }
            }
            Column {
                width: (parent.width - 10) * 0.65
                spacing: 4
                Text { style: Theme.textStyle(); styleColor: Theme.shadow; text: "COMMAND"; color: Theme.dim(); font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.5 }
                Field { id: commandInput; width: parent.width; placeholder: "e.g. discord --start-minimized"; mono: true }
            }
        }
        Item {
            width: parent.width
            height: 34
            Check { id: closeCheck; anchors.verticalCenter: parent.verticalCenter; text: "Close it when the game ends, after" }
            Field {
                id: delayInput
                anchors.left: closeCheck.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                enabled: closeCheck.checked
                opacity: enabled ? 1 : 0.5
                digits: true
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: delayInput.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "seconds"
                color: Theme.textSoft()
                opacity: closeCheck.checked ? 1 : 0.5
                font.family: Theme.body
                font.pixelSize: 13
            }
        }
        Row {
            spacing: 10
            TextButton {
                text: fields.actionText
                onClicked: {
                    const delay = parseInt(delayInput.text)
                    fields.done(nameInput.text.trim(), commandInput.text.trim(), closeCheck.checked,
                                isNaN(delay) ? 10 : Math.max(0, Math.min(600, delay)))
                }
            }
            TextButton { visible: fields.showCancel; text: "Cancel"; onClicked: fields.cancelled() }
        }
    }

    component Field: Rectangle {
        property alias text: input.text
        property string placeholder
        property bool mono: false
        property bool digits: false
        height: 34
        color: "#1b1a20"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text()
            selectionColor: Theme.accent
            selectedTextColor: "#0c0c0f"
            font.family: parent.mono ? "monospace" : Theme.body
            font.pixelSize: parent.mono ? 12 : 13
            maximumLength: parent.digits ? 3 : 400
            validator: parent.digits ? digitsOnly : null
            clip: true
            IntValidator { id: digitsOnly; bottom: 0; top: 600 }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: parent.parent.placeholder
                color: Theme.dim()
                font: input.font
            }
            Accessible.name: parent.placeholder
        }
    }

    component Check: Item {
        id: check
        property string text
        property bool checked: false
        width: box.width + 10 + label.implicitWidth
        height: 24
        Rectangle {
            id: box
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            color: check.checked ? Theme.accent : "transparent"
            border.color: check.checked ? Theme.accent : Theme.track
            HudIcon { anchors.centerIn: parent; visible: check.checked; name: "check"; size: 13; lineWidth: 2.4; color: "#121116" }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: label
            anchors.left: box.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: check.text
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 13
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: check.checked = !check.checked }
        Accessible.role: Accessible.CheckBox
        Accessible.name: text
        Accessible.checked: checked
    }

    /// On or off, in the accent while on.
    component Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool on)
        width: 34
        height: 18
        radius: 0
        color: checked ? Theme.accent : "transparent"
        border.color: checked ? Theme.accent : Theme.track
        Rectangle {
            width: 12
            height: 12
            y: 3
            x: sw.checked ? sw.width - width - 3 : 3
            color: sw.checked ? "#121116" : Theme.muted()
        }
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled(!sw.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: checked
    }
}
