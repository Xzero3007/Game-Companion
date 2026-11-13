import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK
import "armorykit.js" as AK

// BUILDS (board AR3, new; the old Reference tab's lists and import): every
// build with the characters it is on and how far each is, made from
// questlog.gg (the Armory bookmark's file from Downloads, or a saved page),
// from this character as it is, from the strongest players of its class,
// or empty. One build can be on several characters (each keeps its own
// progress); a character can have several and tracks one. Changes to
// what a build aims at make a new version; HISTORY shows progress against
// the version of the time.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var store: ui ? ui.store : null
    property string armed: ""
    property string renaming: ""
    property string versionsOf: ""
    property var files: []
    property var pending: null
    property string note: ""
    spacing: 10

    readonly property string cls: snap && snap.profile ? snap.profile.className || "" : ""
    readonly property var list: { if (!ui) return []; ui.rev; return (store.state.order || []).map((id) => store.state.builds[id]).filter((b) => b) }
    readonly property var mineIds: { if (!ui) return []; ui.rev; const c = ui.charRec; return c ? c.builds || [] : [] }
    // The bookmark: runs on a questlog.gg build page in your browser, reads
    // the page's own state and saves it as a file; it sends nothing.
    readonly property string bookmark: "javascript:(()=>{let nx;try{nx=document.getElementById(\"__nuxt\").__vue_app__.config.globalProperties.$nuxt}catch(e){}const st=nx&&nx.$pinia&&nx.$pinia.state.value;if(!st||!st.A2CharacterBuilder){alert(\"Armory: no questlog.gg character build on this page.\");return}const cb=st.A2CharacterBuilder,dp=st.A2DaevanionPlanner||{},sb=st.A2SkillBuilder||{};const ch=c=>c?{name:c.name,classId:c.classId,url:c.url}:null;const two=o=>({builds:o.builds||[],externalBuilds:o.externalBuilds||[]});const out={armory:\"questlog\",url:location.href,at:new Date().toISOString(),characterBuilder:{character:ch(cb.character),builds:cb.builds||[],externalCharacter:ch(cb.externalCharacter),externalBuilds:cb.externalBuilds||[]},daevanionPlanner:two(dp),skillBuilder:two(sb)};const n=out.characterBuilder.builds.length+out.characterBuilder.externalBuilds.length;const b=new Blob([JSON.stringify(out)],{type:\"application/json\"});const a=document.createElement(\"a\");a.href=URL.createObjectURL(b);a.download=\"armory-\"+((cb.character&&cb.character.url)||\"build\")+\".json\";document.body.appendChild(a);a.click();alert(\"Armory: saved \"+n+\" builds. Pick the file in Game Companion's Armory (BUILDS tab).\")})()"

    function arm(what, f) {
        if (armed !== what) { armed = what; disarm.restart(); return }
        armed = ""
        f()
    }
    Timer { id: disarm; interval: 3000; onTriggered: tab.armed = "" }
    function progressOf(key, b) {
        const s = key === store.current ? snap : store.loadSnap(key)
        const p = s ? BK.progress(s, b, store.state.chars[key], store.prices) : null
        return p && p.total != null ? Math.round(p.total * 100) + " %" : "—"
    }
    function make(kind) {
        if (!snap) return
        const name = snap.profile ? snap.profile.name : "Character"
        if (kind === "copy") store.makeBuild(name + "'s build", "PvE", BK.referenceOfSnapshot(snap), "a copy of " + name, BK.targetsOfSnapshot(snap))
        else if (kind === "top") store.makeBuild("Top " + cls + "s", "PvE", null, "the strongest " + cls + "s (Shugo.GG)", BK.targetsOfTop(snap))
        else store.makeBuild("New build", "PvE", null, "own", null)
        note = "Made and put on " + name + "."
    }
    function lookFiles() {
        try { files = JSON.parse(Aion2.armoryFiles()) } catch (e) { files = [] }
        note = files.length ? "" : "No armory-*.json in your Downloads folder yet: click the Armory bookmark on a questlog.gg build page first."
    }
    function readFile(name) {
        let doc = null
        try { doc = JSON.parse(Aion2.armoryFile(name) || "null") } catch (e) { doc = null }
        const builds = doc ? ck.readQuestlogBuilds(doc) : []
        if (builds.length) { pending = builds; note = builds.length + " builds in " + name + ": add the ones to keep." }
        else if (doc && (Array.isArray(doc.gear) || Array.isArray(doc.skills))) addRef(doc, doc.name || "Build", doc.source || "a build code")
        else note = name + ": no build in it."
    }
    function addRef(ref, name, source) {
        if (!ref || (!(ref.gear || []).length && !(ref.skills || []).length && !(ref.boards || []).length)) { note = "No build found in that."; return }
        const b = store.makeBuild(name || ref.name || "Build", "PvE", ref, source || ref.source || "questlog.gg", null)
        if (b) note = b.name + ": " + (ref.gear || []).length + " pieces, " + (ref.skills || []).length + " skills, " + Object.keys(ref.daev || {}).length + " Daevanion boards; put on this character."
    }
    function readPasted(text) {
        const t = String(text || "").trim()
        if (!t) return
        if (t.charAt(0) === "{") {
            let doc = null
            try { doc = JSON.parse(t) } catch (e) { note = "That isn't a build code."; return }
            const builds = ck.readQuestlogBuilds(doc)
            if (builds.length) { pending = builds; return }
            addRef(doc, doc.name, doc.source || "a build code")
            return
        }
        let ref = null
        try { ref = ck.readQuestlogPage(t) } catch (e) { ref = null }
        addRef(ref, ref ? ref.name : "", "a saved questlog.gg page")
    }

    AUi.Note {
        visible: !tab.snap
        width: parent.width
        text: "Read a character first (play it, or look it up above): builds are put on the character shown."
    }

    // ---- make one ----
    AUi.Box {
        width: parent.width
        AUi.Title { text: "Make a build for " + (tab.snap && tab.snap.profile ? tab.snap.profile.name : "this character") }
        Flow {
            width: parent.width
            spacing: 6
            Chip { text: "From questlog.gg (Downloads)"; onClicked: tab.lookFiles() }
            Chip { enabled: !!tab.snap; text: "A copy of this character"; onClicked: tab.make("copy") }
            Chip { visible: !!tab.snap && !!tab.ck.topOf(tab.cls); text: "The strongest " + tab.cls + "s' picks"; onClicked: tab.make("top") }
            Chip { enabled: !!tab.snap; text: "Empty"; onClicked: tab.make("empty") }
        }
        AUi.Line { visible: tab.note !== ""; width: parent.width; text: tab.note; color: Theme.accentLight; font.pixelSize: 11; wrapMode: Text.WordWrap; elide: Text.ElideNone }
        Flow {
            visible: tab.files.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: tab.files
                delegate: Chip {
                    required property var modelData
                    text: modelData.name + " · " + tab.store.when(modelData.at)
                    onClicked: tab.readFile(modelData.name)
                }
            }
        }
        // The builds in a file, to pick.
        Repeater {
            model: tab.pending || []
            delegate: Rectangle {
                required property var modelData
                readonly property var r: tab.ck.questlogReference(modelData, tab.snap)
                width: parent.width
                height: 38
                color: "#24222a"
                Column {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 100
                    AUi.Line { width: parent.width; text: modelData.name || "(no name)"; font.bold: true }
                    AUi.Line {
                        width: parent.width
                        text: [modelData.classId, parent.parent.r.gearScore ? "gear score ≈ " + tab.ui.fmt(parent.parent.r.gearScore) : null,
                            Object.keys(modelData.soul || {}).length ? "soul bindings on " + Object.keys(modelData.soul).length + " pieces" : "no soul bindings",
                            (modelData.skills || []).length ? "skills: " + (modelData.skillName || "yes") : "no skills",
                            Object.keys(modelData.daev || {}).length ? "Daevanion: " + (modelData.daevName || "yes") : "no Daevanion"].filter((x) => x).join(" · ")
                        color: Theme.dim()
                        font.pixelSize: 10
                    }
                }
                Chip { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "Add"; onClicked: tab.addRef(parent.r, modelData.name, "questlog.gg") }
            }
        }
        Chip { visible: !!tab.pending; text: "Close the list"; onClicked: tab.pending = null }
        AUi.Note {
            width: parent.width
            text: "questlog.gg: open the character's build page in your browser and click the Armory bookmark (below): it saves armory-<character>.json in Downloads, with every build of that character (gear with soul bindings, Arcana, Daevanion nodes, skill levels). Then “From questlog.gg” reads it here. Nothing is sent anywhere."
        }
        Row {
            spacing: 8
            Chip { id: bmChip; text: bmBox.visible ? "Hide the bookmark" : "The Armory bookmark"; onClicked: bmBox.visible = !bmBox.visible }
            Chip { text: pasteBox.visible ? "Hide" : "Paste a saved page or build code"; onClicked: pasteBox.visible = !pasteBox.visible }
        }
        Column {
            id: bmBox
            visible: false
            width: parent.width
            spacing: 4
            AUi.Note { width: parent.width; text: "Once: make a new bookmark in your browser, name it “Armory”, and paste this as its address (URL)." }
            Rectangle {
                width: parent.width
                height: 54
                color: "#121116"
                border.color: "#3a3842"
                clip: true
                TextEdit {
                    id: bmText
                    anchors.fill: parent
                    anchors.margins: 6
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    text: tab.bookmark
                    color: Theme.muted()
                    selectionColor: Theme.accent
                    font.family: "monospace"
                    font.pixelSize: 10
                }
            }
            Chip { text: "Copy"; onClicked: { bmText.selectAll(); bmText.copy(); bmText.deselect(); tab.note = "The bookmark is copied." } }
        }
        Column {
            id: pasteBox
            visible: false
            width: parent.width
            spacing: 4
            AUi.Note { width: parent.width; text: "A build page saved from the browser (Ctrl+S on its Equipment, Skills or Daevanion tab: items, levels and points, no soul bindings), or a build code." }
            Rectangle {
                width: parent.width
                height: 60
                color: "#121116"
                border.color: pasteText.activeFocus ? Theme.accent : "#3a3842"
                clip: true
                TextEdit {
                    id: pasteText
                    anchors.fill: parent
                    anchors.margins: 6
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    color: Theme.text()
                    selectionColor: Theme.accent
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            Chip { text: "Read what is pasted"; onClicked: { tab.readPasted(pasteText.text); pasteText.text = "" } }
        }
    }

    // ---- every build ----
    AUi.Head { text: tab.list.length ? "YOUR BUILDS" : "NO BUILDS YET" }
    Repeater {
        model: tab.list
        delegate: AUi.Box {
            id: card
            required property var modelData
            readonly property var b: modelData
            readonly property bool onMe: tab.mineIds.indexOf(b.id) >= 0
            readonly property bool active: !!tab.build && tab.build.id === b.id
            readonly property var chars: { tab.ui.rev; return BK.charsOf(tab.store.state, b.id) }
            width: tab.width
            color: active ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.08) : "#1b1a20"
            Item {
                width: parent.width
                height: 26
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    AUi.Field {
                        visible: tab.renaming === card.b.id
                        width: 200
                        text: card.b.name
                        onAccepted: { tab.store.renameBuild(card.b.id, text.trim(), null); tab.renaming = "" }
                    }
                    AUi.Title { visible: tab.renaming !== card.b.id; text: card.b.name; color: card.active ? Theme.accent : Theme.text() }
                    Chip {
                        text: card.b.kind
                        onClicked: tab.store.renameBuild(card.b.id, null, BK.KINDS[(BK.KINDS.indexOf(card.b.kind) + 1) % BK.KINDS.length])
                    }
                    AUi.Line {
                        anchors.verticalCenter: parent.verticalCenter
                        text: [card.b.cls, "from " + card.b.source, "v" + card.b.version, card.b.ref ? (card.b.ref.gear || []).length + " pieces" : "no gear"].filter((x) => x).join(" · ")
                        color: Theme.dim()
                        font.pixelSize: 11
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    AUi.Line { visible: card.active; anchors.verticalCenter: parent.verticalCenter; text: "ACTIVE HERE"; color: Theme.accent; font.family: Theme.display; font.bold: true; font.pixelSize: 11 }
                    Chip { visible: !card.active && !!tab.store.current; text: card.onMe ? "Make active" : "Put on " + (tab.snap && tab.snap.profile ? tab.snap.profile.name : "this character"); onClicked: card.onMe ? tab.store.setActive(card.b.id) : tab.store.putOn(tab.store.current, card.b.id) }
                    Chip { visible: card.onMe; text: "Take off"; onClicked: tab.store.takeOff(tab.store.current, card.b.id) }
                    Chip { text: tab.renaming === card.b.id ? "Done" : "Rename"; onClicked: tab.renaming = tab.renaming === card.b.id ? "" : card.b.id }
                    Chip { text: tab.armed === "rm" + card.b.id ? "Press again to remove" : "Remove"; on: tab.armed === "rm" + card.b.id; onClicked: tab.arm("rm" + card.b.id, () => tab.store.removeBuild(card.b.id)) }
                }
            }
            Flow {
                width: parent.width
                spacing: 14
                AUi.Line { text: card.chars.length ? "On:" : "On no character."; color: Theme.muted(); font.pixelSize: 11 }
                Repeater {
                    model: card.chars
                    delegate: AUi.Line {
                        required property var modelData
                        text: modelData.name + " " + tab.progressOf(modelData.key, card.b) + (modelData.active ? "" : " (not tracked)")
                        color: modelData.key === tab.store.current ? Theme.text() : Theme.muted()
                        font.pixelSize: 11
                    }
                }
            }
            AUi.Line {
                width: parent.width
                text: (tab.versionsOf === card.b.id ? "▾ " : "▸ ") + "Versions: " + card.b.versions[card.b.versions.length - 1].what + " · " + tab.store.when(card.b.versions[card.b.versions.length - 1].at)
                color: Theme.dim()
                font.pixelSize: 11
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tab.versionsOf = tab.versionsOf === card.b.id ? "" : card.b.id }
            }
            Repeater {
                model: tab.versionsOf === card.b.id ? card.b.versions.slice().reverse() : []
                delegate: AUi.Line {
                    required property var modelData
                    x: 14
                    width: card.width - 34
                    text: "v" + modelData.v + " · " + tab.store.when(modelData.at) + " · " + modelData.what
                    color: Theme.muted()
                    font.pixelSize: 11
                }
            }
        }
    }
    AUi.Note {
        width: parent.width
        text: "Everything a build aims at is changed in its tabs: GEAR (each slot's target and levels, slots left out), SOUL BINDING, SKILLS, DAEVANION (the build's nodes come with it) and GOALS (its gear score). Each change within ten minutes makes one new version."
    }
}
