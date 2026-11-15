// The same checks as run.js under Qt's own JavaScript (the app's engine):
// Run with a QML runner that provides `gcHost.readFile(path)` (plain `qml` lacks it).
// GC_REPO must name the repository's folder.
import QtQml
import "../../../qml/poe2/ee2kit.js" as Kit
import "run.js" as T
QtObject {
    id: root
    property var timers: ({})
    property int nextId: 1
    property Component timerComp: Component { Timer { property var cb; onTriggered: { cb(); destroy() } } }
    readonly property string repo: Qt.resolvedUrl("../../../").toString().replace("file://", "")
    Component.onCompleted: {
        const host = {
            request: null,
            timer: function (ms, cb) { const t = timerComp.createObject(root, { interval: Math.max(1, ms), cb: cb }); const id = nextId++; timers[id] = t; t.start(); return id },
            cancel: function (id) { const t = timers[id]; if (t) { t.stop(); t.destroy(); delete timers[id] } },
            readData: function (p) { return gcHost.readFile(repo + "data/poe2/" + p) },
            log: function (t) { console.log(t) }
        }
        const items = JSON.parse(gcHost.readFile(repo + "tools/poe2-ee2/test/items.json"))
        T.run(Kit.EE2, host, items, function (t) { console.log(t) }, function (ok) { console.log(ok ? "V4 OK" : "V4 FAILED"); Qt.quit() })
    }
}
