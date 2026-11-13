import QtQuick
import GameCompanion

// Waits for the answers to the Games launch option calls: they return a
// request number at once and answer later by `Games.launchResult`. `ask`
// keeps what to do with the answer (parsed JSON) until it comes.
QtObject {
    id: requests
    property var waiting: ({})
    /// How many answers are still out.
    property int count: 0
    readonly property bool busy: count > 0

    function ask(request, then) {
        if (request < 0) return
        waiting[request] = then
        count += 1
    }

    /// Stops waiting for a request a newer one replaced (a superseded check
    /// gets no answer at all, which would keep `busy` on).
    function forget(request) {
        if (request < 0 || waiting[request] === undefined) return
        delete waiting[request]
        count -= 1
    }

    property Connections link: Connections {
        target: Games
        function onLaunchResult(request, json) {
            const then = requests.waiting[request]
            if (then === undefined) return
            delete requests.waiting[request]
            requests.count -= 1
            let value = null
            try { value = JSON.parse(json) } catch (e) { value = null }
            then(value)
        }
    }
}
