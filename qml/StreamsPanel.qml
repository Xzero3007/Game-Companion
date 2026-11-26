import QtQuick
import GameCompanion
import "theme.js" as Theme

// Streams: Twitch, YouTube and the user's own Jellyfin server (home network
// only). The running game's lists come first, under its purple tag; a click
// plays in that site's video window over the game.
Panel {
    id: panel
    panelId: "streams"
    title: "Streams"
    icon: "tv"
    width: 520
    minWidth: 420
    stretchy: true

    signal playRequested(var what)
    /// What plays now in each window (to mark its row).
    property string playingTwitch: ""
    property string playingYoutube: ""
    property string playingJellyfin: ""

    readonly property var game: JSON.parse(Streams.game)
    readonly property var twitchList: JSON.parse(Streams.twitch)
    readonly property var youtubeList: JSON.parse(Streams.youtube)
    readonly property var favs: JSON.parse(Streams.favourites)
    readonly property var channels: JSON.parse(Streams.channels)
    readonly property var channelPictures: JSON.parse(Streams.channelPictures)
    // Channels without a picture yet: asked once while the Channels list shows.
    readonly property bool picturesWanted: visible && listKind === "channels" && channels.length > 0
    onPicturesWantedChanged: if (picturesWanted) Streams.fetchChannelPictures()
    onChannelsChanged: if (picturesWanted) Streams.fetchChannelPictures()
    readonly property var account: JSON.parse(Streams.account)
    readonly property bool onTwitch: Streams.tab === "twitch"
    readonly property bool onJelly: Streams.tab === "jellyfin"
    readonly property var jellyList: JSON.parse(Jellyfin.items)
    readonly property var listWanted: listKind === "jelly" ? jellyList : listKind === "playlists" ? playlistsShown : onTwitch ? twitchList : youtubeShown
    /// The YouTube list in its chosen order (Streams' `filters.sorts`; MN,
    /// 0.8.43): the game's search is asked of YouTube in its order, the
    /// others are sorted as loaded.
    readonly property var sortDefaults: ({ game: "date", subscriptions: "newest", channel: "newest", trending: "own", playlist: "own", history: "own" })
    readonly property string ytSort: (filters.sorts && filters.sorts[ytView]) || sortDefaults[ytView] || ""
    // The game's search comes in YouTube's order; "Newest first" is also
    // sorted here by the dates as they come in (YouTube's upload-date order
    // was loose, MN 0.8.51: "5 days ago" before "2 h ago").
    readonly property var youtubeShown: ytView === "game" ? (ytSort === "date" ? sortVideos(youtubeList, "newest") : youtubeList)
        : sortVideos(youtubeList, ytSort)
    function sortVideos(list, key) {
        if (!key || key === "own" || list.length < 2) return list
        const date = (v) => v.published || ""
        const length = (v) => v.duration > 0 ? v.duration : 0
        // Videos without a date or a length go last either way.
        const by = key === "newest" ? (a, b) => date(a) === date(b) ? 0 : date(a) < date(b) ? 1 : -1
                 : key === "oldest" ? (a, b) => !date(a) !== !date(b) ? (date(a) ? -1 : 1) : date(a) === date(b) ? 0 : date(a) < date(b) ? -1 : 1
                 : key === "longest" ? (a, b) => length(b) - length(a)
                 : (a, b) => !length(a) !== !length(b) ? (length(a) ? -1 : 1) : length(a) - length(b)
        // Stable: equal ones keep the list's order.
        return list.map((v, i) => [v, i]).sort((x, y) => by(x[0], y[0]) || x[1] - y[1]).map((x) => x[0])
    }
    function sortOptions(view) {
        if (view === "game") return [{ id: "relevance", name: "Relevance" }, { id: "date", name: "Newest first" }, { id: "views", name: "Most viewed" }]
        const own = { playlist: "Playlist order", history: "Last watched", trending: "Trending order" }[view]
        if (!own && view !== "subscriptions" && view !== "channel") return []
        let o = own ? [{ id: "own", name: own }] : []
        return o.concat([{ id: "newest", name: "Newest first" }, { id: "oldest", name: "Oldest first" }, { id: "longest", name: "Longest" }, { id: "shortest", name: "Shortest" }])
    }
    readonly property var ytSortOptions: onTwitch || onJelly || listKind !== "video" ? [] : sortOptions(ytView)
    readonly property string ytSortName: { const o = ytSortOptions.find((x) => x.id === ytSort); return o ? o.name : "" }
    /// What the list and the tiles show: set from `listWanted` by `swapList`,
    /// which keeps the place when the same list only grew or was refreshed
    /// (a new array would put a view back at its top).
    property var listModel: []
    /// Which list it is: a different one starts at its top.
    readonly property string listKey: Streams.tab + "|" + listKind + "|"
        + (onJelly ? Jellyfin.view + "|" + (jfPath.length > 0 ? jfPath[jfPath.length - 1].id : "")
           : onTwitch ? twView + "|" + (arg ? arg.name || arg.login || "" : "")
           : ytView + "|" + (arg ? arg.id || "" : "") + "|" + (channel ? channel.id : "") + "|" + (ytView === "trending" ? Streams.trendSection : "") + "|" + ytSort)
        + "|" + (searchShown ? search.text : "")
    property string modelKey: ""
    function itemKey(x) { return x ? String(x.id || x.login || x.name || "") : "" }
    onListWantedChanged: swapList()
    function swapList() {
        const v = listArea.shown
        const sameList = listKey === modelKey && v && (v === list || v === grid)
        const keep = sameList ? placeIn(v, listModel) : null
        modelKey = listKey
        listModel = listWanted
        backTo(v, keep, listWanted, v === list ? listWheel : gridWheel)
    }
    /// The first row seen in `v` and how far it is scrolled past (null at
    /// the top).
    function placeIn(v, model) {
        if (!v || !model || model.length === 0 || v.contentY - v.originY <= 1) return null
        const at = v.indexAt(v.width / 2, v.contentY + 1)
        const first = at >= 0 ? itemKey(model[at]) : ""
        if (!first) return null
        const item = v.itemAtIndex(at)
        return { key: first, at: at, off: item ? v.contentY - item.y : 0 }
    }
    /// Scrolls `v`, which now shows `model`, back to the row `keep` saw.
    function backTo(v, keep, model, wheel) {
        if (!keep) return
        const index = model.findIndex((x) => itemKey(x) === keep.key)
        if (index < 0) return
        if (index !== keep.at) wheel.stop()
        v.forceLayout()
        v.positionViewAtIndex(index, ListView.Beginning)
        v.contentY += keep.off
    }
    /// The channel list as shown: swapped like `listModel`, so putting a
    /// channel into a group keeps the place (MN, 2026-11-16: it jumped to
    /// the top). Another group starts at its top.
    property var channelModel: []
    property string channelModelGroup: ""
    onChannelsShownChanged: swapChannels()
    function swapChannels() {
        const v = listArea.shown
        const sameList = channelModelGroup === Streams.group && (v === channelList || v === channelGrid)
        const keep = sameList ? placeIn(v, channelModel) : null
        channelModelGroup = Streams.group
        channelModel = channelsShown
        backTo(v, keep, channelsShown, v === channelList ? channelListWheel : channelGridWheel)
    }
    readonly property var jfAccount: Jellyfin.account.length > 0 ? JSON.parse(Jellyfin.account) : null
    /// Jellyfin's libraries: the way in (library, show, season), each
    /// `{ id, type, collection, seriesId, name }`.
    property var jfPath: []
    property bool editingGame: false
    /// YouTube: the channel whose videos show ("" for none).
    property var channel: null
    /// The open thing of a list: a YouTube playlist {id, name}, a Twitch
    /// category {name, title} or a Twitch channel's recordings {login, name}.
    property var arg: null
    readonly property var groups: JSON.parse(Streams.groups)
    readonly property var filters: JSON.parse(Streams.filters)
    readonly property var searchFilter: JSON.parse(Streams.searchFilter)
    readonly property var twitchFilter: JSON.parse(Streams.twitchFilter)
    readonly property var liveNews: JSON.parse(Streams.liveNews)
    readonly property var alertsOff: JSON.parse(Streams.alertsOff)
    readonly property var playlists: JSON.parse(Library.playlists)
    /// The playlists as the tab shows them: narrowed by the search, sorted.
    property string playlistSort: "played"
    readonly property var playlistsShown: {
        const t = search.text.trim().toLowerCase()
        let l = playlists.filter((p) => !t || p.name.toLowerCase().indexOf(t) >= 0 || (matchVideos && p.titles.indexOf(t) >= 0))
        const by = { played: (a, b) => b.played - a.played || b.updated - a.updated, created: (a, b) => b.created - a.created,
                     updated: (a, b) => b.updated - a.updated, az: (a, b) => a.name.localeCompare(b.name), za: (a, b) => b.name.localeCompare(a.name) }
        return l.sort(by[playlistSort] || by.played)
    }
    property bool matchVideos: false
    readonly property string ytView: Streams.youtubeView
    readonly property string twView: Streams.twitchView
    /// What the list shows: "jelly", "twitch", "categories", "recordings",
    /// "video", "channels" or "playlists".
    readonly property string listKind: onJelly ? "jelly"
        : onTwitch ? (twView === "categories" ? "categories" : twView === "recordings" ? "recordings" : "twitch")
        : ytView === "channels" ? "channels" : ytView === "playlists" ? "playlists" : "video"
    /// The open YouTube list's videos: which have HDR is looked at in the
    /// background (Streams.wantHdr; "[]" when none shows), never while a
    /// game runs (MN, 2026-11-19).
    readonly property string hdrIds: visible && listKind === "video" && !onTwitch && !onJelly
        ? JSON.stringify(youtubeShown.filter((v) => !v.live && !!v.id).map((v) => v.id)) : "[]"
    onHdrIdsChanged: Streams.wantHdr(hdrIds)
    readonly property bool gameRunning: Games.running !== ""
    onGameRunningChanged: { Streams.setHdrPaused(gameRunning); if (!gameRunning) editingGame = false; if (visible) leaveGame() }
    /// The game's tab and its preset show only while a game runs (MN,
    /// 2026-11-23: the last game stood there with none running). Without one
    /// its view gives way to Following (Twitch) or Subscriptions (YouTube).
    function gameless(s) {
        if (gameRunning || s.tab === "jellyfin") return s
        const twitchGame = s.tab === "twitch" && (s.view === "game" || ((s.view === "category" || s.view === "recordings") && !s.arg))
        if (s.view !== "game" && !twitchGame) return s
        return Object.assign({}, s, { view: s.tab === "twitch" ? "following" : "subscriptions", arg: null })
    }
    function leaveGame() {
        if (!loadedOnce) return
        const s = stateNow()
        if (gameless(s).view !== s.view) go(gameless(s))
    }
    readonly property var channelsShown: Streams.group ? channels.filter((c) => c.groups.indexOf(Streams.group) >= 0) : channels
    /// The search field serves the search, and narrows the history, the
    /// playlists and Twitch's categories.
    readonly property bool searchShown: onJelly ? (!!jfAccount && Jellyfin.view === "search")
        : onTwitch ? (twView === "search" || twView === "categories")
        : (ytView === "search" || ytView === "history" || ytView === "playlists")

    // The count, or how far a long load is (YouTube's subscriptions).
    badge: onJelly ? (Jellyfin.state === "ready" && jfAccount ? Jellyfin.message.toUpperCase() : "")
        : onTwitch ? (Streams.twitchState === "ready" ? Streams.twitchMessage.toUpperCase() : "")
        : ytView === "playlists" ? playlists.length + " PLAYLISTS"
        : (Streams.youtubeState === "ready" || Streams.youtubeState === "loading" ? Streams.youtubeMessage.toUpperCase() : "")
    readonly property bool tiles: Streams.grid
    readonly property bool channelsView: listKind === "channels"

    // Back and forth through tabs, lists, searches and channels, as in a
    // browser: { tab, view, text, channel }.
    property var history: []
    property int at: -1
    readonly property bool canBack: at > 0
    readonly property bool canForward: at < history.length - 1
    function stateNow() {
        return { tab: Streams.tab, view: onJelly ? Jellyfin.view : onTwitch ? Streams.twitchView : Streams.youtubeView,
                 text: search.text, channel: channel, path: jfPath, arg: arg }
    }
    function go(s) {
        let h = history.slice(0, at + 1)
        // An empty search tab is replaced by its search.
        const last = h.length > 0 ? h[h.length - 1] : null
        if (last && last.tab === s.tab && last.view === "search" && !last.text && s.view === "search") h.pop()
        h.push(s)
        if (h.length > 50) h = h.slice(h.length - 50)
        history = h
        at = h.length - 1
        apply(s)
    }
    function apply(s) {
        s = gameless(s)
        if (Streams.tab !== s.tab) Streams.chooseTab(s.tab)
        search.text = s.text || ""
        channel = s.channel || null
        arg = s.arg || null
        if (s.tab === "jellyfin") {
            jfPath = s.path || []
            if (s.view === "folder" && jfPath.length > 0) Jellyfin.load("folder", JSON.stringify(jfPath[jfPath.length - 1]))
            else Jellyfin.load(s.view === "folder" ? "libraries" : s.view, s.view === "search" ? search.text : "")
        } else if (s.tab === "twitch") {
            if (s.view === "category" && arg) Streams.loadTwitch("category", arg.name)
            else if (s.view === "recordings" && arg) Streams.loadTwitch("recordings", arg.login)
            else Streams.loadTwitch(s.view === "category" || s.view === "recordings" ? "game" : s.view,
                                    s.view === "search" || s.view === "categories" ? search.text : "")
        } else if (s.view === "channel" && channel) {
            Streams.loadYoutube("channel", channel.id)
        } else if (s.view === "playlist" && arg) {
            Streams.loadYoutube("playlist", arg.id)
        } else if (s.view === "trending") {
            Streams.loadYoutube("trending", s.text || Streams.trendSection)
            search.text = ""
        } else if (s.view === "history") {
            Streams.loadYoutube("history", search.text)
        } else {
            Streams.loadYoutube(s.view === "channel" ? "channels" : s.view, s.view === "search" ? search.text : "")
        }
        if (s.view === "search" && !s.text) search.forceActiveFocus()
    }
    function back() { if (canBack) { at = at - 1; apply(history[at]) } }
    function forward() { if (canForward) { at = at + 1; apply(history[at]) } }
    Shortcut {
        sequences: ["Alt+Left", StandardKey.Back]
        enabled: panel.visible && !Companion.locked
        onActivated: panel.back()
    }
    Shortcut {
        sequences: ["Alt+Right", StandardKey.Forward]
        enabled: panel.visible && !Companion.locked
        onActivated: panel.forward()
    }

    property bool loadedOnce: false
    onVisibleChanged: if (visible) { if (!loadedOnce) firstLoad(); else leaveGame() }
    Component.onCompleted: { swapList(); swapChannels(); if (visible && !loadedOnce) firstLoad(); Streams.setHdrPaused(gameRunning); Streams.wantHdr(hdrIds) }
    Component.onDestruction: Streams.wantHdr("[]")
    function firstLoad() {
        loadedOnce = true
        Streams.refreshAccount()
        if (Streams.youtubeView === "channel") Streams.loadYoutube("channels", "")
        if (Streams.youtubeView === "playlist") Streams.loadYoutube("playlists", "")
        if (Streams.twitchView === "category" || Streams.twitchView === "recordings") Streams.loadTwitch(gameRunning ? "game" : "following", "")
        const s = gameless(stateNow())
        history = [s]
        at = 0
        if (s.view !== stateNow().view) apply(s)
        else reload()
    }
    function reload() {
        if (onJelly) {
            if (!jfAccount) return
            if (Jellyfin.view === "search") { if (search.text.trim().length > 0) Jellyfin.load("search", search.text) }
            else if (Jellyfin.view === "folder" && jfPath.length > 0) Jellyfin.load("folder", JSON.stringify(jfPath[jfPath.length - 1]))
            else Jellyfin.load(Jellyfin.view === "folder" ? "libraries" : Jellyfin.view, "")
        } else if (onTwitch) {
            if (Streams.twitchView === "search") { if (search.text.trim().length > 0) Streams.loadTwitch("search", search.text) }
            else if (twView === "category" && arg) Streams.loadTwitch("category", arg.name)
            else if (twView === "recordings" && arg) Streams.loadTwitch("recordings", arg.login)
            else Streams.loadTwitch(twView === "categories" ? "categories" : Streams.twitchView, twView === "categories" ? search.text : "")
        } else {
            if (Streams.youtubeView === "search") { if (search.text.trim().length > 0) Streams.loadYoutube("search", search.text) }
            else if (Streams.youtubeView === "channel" && channel) Streams.loadYoutube("channel", channel.id)
            else if (ytView === "playlist" && arg) Streams.loadYoutube("playlist", arg.id)
            else if (ytView === "history") Streams.loadYoutube("history", search.text)
            else if (ytView === "trending") Streams.loadYoutube("trending", Streams.trendSection)
            else if (Streams.youtubeView === "channels" || ytView === "playlists") return
            else Streams.loadYoutube(Streams.youtubeView === "channel" ? "subscriptions" : Streams.youtubeView, "")
        }
    }
    function runSearch() {
        const text = search.text.trim()
        if (onTwitch && twView === "categories") { Streams.loadTwitch("categories", text); return }
        if (!onTwitch && !onJelly && (ytView === "history" || ytView === "playlists")) return
        if (text.length === 0) return
        if (Streams.tab === "youtube") {
            // A pasted link plays at once.
            const id = Streams.videoId(text)
            if (id.length > 0) { panel.playRequested({ kind: "youtube", id: id, title: "", name: "" }); return }
        }
        go({ tab: Streams.tab, view: "search", text: text, channel: null })
    }
    /// When a video came out: within a week how long ago, after that its
    /// date ("12 Oct", with the year when not this one). A rough date
    /// (yt-dlp's reading of YouTube's "3 weeks ago") stays rough.
    function ago(iso, rough) {
        if (!iso) return ""
        const t = Date.parse(iso)
        const s = (Date.now() - t) / 1000
        if (!(s >= 0)) return ""
        if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        const d = Math.round(s / 86400)
        if (d < 7) return d === 1 ? "yesterday" : d + " days ago"
        if (rough) {
            const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s") + " ago"
            return d < 30 ? plural(Math.round(d / 7), "week") : d < 365 ? plural(Math.round(d / 30), "month") : plural(Math.round(d / 365), "year")
        }
        const date = new Date(t)
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return date.getDate() + " " + months[date.getMonth()] + (date.getFullYear() === new Date().getFullYear() ? "" : " " + date.getFullYear())
    }
    /// A video's channel id in full: YouTube's feeds give it without its
    /// "UC" at their top (stored so before 0.8.41).
    function chanId(v) {
        const id = v && v.channelId ? String(v.channelId) : ""
        return id.length === 22 && id.indexOf("UC") !== 0 ? "UC" + id : id
    }
    /// Opens a video's channel (its videos, newest first).
    function openChannelOf(v) {
        const id = chanId(v)
        if (id) go({ tab: "youtube", view: "channel", text: "", channel: { id: id, name: v.channel || "" } })
    }
    function clock(sec) {
        sec = Math.floor(sec || 0)
        if (sec <= 0) return ""
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
        const two = (n) => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s)
    }
    // Jellyfin: into a library, a show or a season; or play.
    function jfOpen(it) {
        if (it.openable) {
            const at = jfPath.length > 0 ? jfPath[jfPath.length - 1] : null
            const step = { id: it.id, type: it.type, collection: it.collection || (at ? at.collection : ""),
                           seriesId: it.seriesId || (at && at.type === "Series" ? at.id : ""), name: it.name }
            go({ tab: "jellyfin", view: "folder", text: "", channel: null, path: jfPath.concat([step]) })
        } else if (it.playable) {
            panel.playRequested({ kind: "jellyfin", id: it.id, title: it.name, name: it.sub, item: it, start: it.position || 0 })
        }
    }
    function timeLeft(it) {
        const s = Math.max(0, (it.runtime || 0) - (it.position || 0))
        if (!(it.position > 0) || s <= 0) return ""
        const m = Math.round(s / 60)
        if (m < 1) return "under a minute left"
        return (m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min") + " left"
    }
    /// Plays a YouTube video; inside a playlist (or a list played through)
    /// the rest follows at once (`through`). Started from any other list,
    /// the videos after it in the shown order are what comes next: the
    /// player's NEXT and UP NEXT, and with AUTOPLAY on they follow too.
    function playVideo(v, queue, index, through) {
        let q = queue || null
        let at = index || 0
        if (!q) {
            q = youtubeShown.filter((x) => !!x.id && (!x.live || x.id === v.id))
            at = q.findIndex((x) => x.id === v.id)
            if (at < 0) { q = null; at = 0 }
        }
        const all = through !== false && !!queue
        panel.playRequested({ kind: "youtube", id: v.id, title: v.title, name: v.channel, video: v,
                              queue: q, index: at, through: all, loop: all && loopList,
                              playlist: arg && ytView === "playlist" ? arg.id : "" })
    }
    property bool loopList: false
    function playAll(shuffle) {
        let q = youtubeShown.slice()
        if (q.length === 0) return
        if (shuffle) for (let i = q.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = q[i]; q[i] = q[j]; q[j] = t }
        if (arg) Library.played(arg.id)
        playVideo(q[0], q, 0)
    }
    function playTwitch(c) {
        panel.playRequested({ kind: "twitch", id: c.login, name: c.name, game: c.game, title: c.title })
    }
    function playRecording(r) {
        panel.playRequested({ kind: r.kind === "clip" ? "twitchclip" : "twitchvod", id: r.id, name: arg ? arg.name : "", title: r.title, login: arg ? arg.login : "" })
    }
    function openRecordings(c) {
        go({ tab: "twitch", view: "recordings", text: "", channel: null, arg: { login: c.login, name: c.name } })
    }
    function openPlaylist(p) {
        go({ tab: "youtube", view: "playlist", text: "", channel: null, arg: { id: p.id, name: p.name } })
    }
    // The menu beside a video or channel: placed by the button, kept inside
    // the panel.
    property var menuFor: null
    property string menuKind: ""
    function openMenu(button, kind, what) {
        const at = button.mapToItem(panel, 0, button.height)
        menuFor = what
        menuKind = kind
        menuButton = button
        menu.options = menuOptions(kind, what)
        menu.x = Math.max(4, Math.min(at.x - menu.width + button.width, panel.width - menu.width - 4))
        menu.y = Math.max(4, Math.min(at.y, panel.height - menu.height - 4))
        menu.open = true
    }
    function menuOptions(kind, w) {
        if (kind === "video") {
            const m = JSON.parse(Library.mark(w.id))
            let o = [{ id: "add", name: "Add to playlist ▸" }]
            if (ytView === "playlist" && arg) {
                o.push({ id: "remove", name: "Remove from playlist" })
                if (!tiles && ytSort === "own") o.push({ id: "up", name: "Move up" }, { id: "down", name: "Move down" })
            }
            o.push({ id: "watched", name: m.done ? "Mark as not watched" : "Mark as watched" })
            if (ytView === "history") o.push({ id: "forget", name: "Remove from history" })
            if (w.channelId && !(ytView === "channel" && channel && channel.id === chanId(w))) o.push({ id: "channel", name: "Go to channel" })
            if (w.channelId) o.push({ id: "groups", name: "Channel into group ▸" })
            if (w.channelId || w.channel) o.push({ id: "hide", name: "Hide this channel" })
            return o
        }
        if (kind === "add") {
            let o = playlists.map((p) => ({ id: "to:" + p.id, name: (JSON.parse(Library.mark(w.id)).lists.indexOf(p.id) >= 0 ? "✓ " : "") + p.name }))
            o.push({ id: "new", name: "+ New playlist" })
            return o
        }
        if (kind === "videogroups") {
            const c = channels.find((x) => x.id === chanId(w))
            let o = groups.map((g) => ({ id: "group:" + g, name: (c && c.groups.indexOf(g) >= 0 ? "✓ " : "") + g }))
            o.push({ id: "newgroup", name: "+ New group" })
            return o
        }
        if (kind === "twitch") {
            let o = [{ id: "recordings", name: "Past broadcasts & clips" }]
            if (Streams.alerts) o.push({ id: "alert", name: alertsOff.indexOf(w.login.toLowerCase()) >= 0 ? "Live notes on" : "No live notes" })
            return o
        }
        if (kind === "channel") {
            let o = [{ id: "sub", name: w.freetube ? "Subscribe here" : "Unsubscribe" }]
            o = o.concat(groups.map((g) => ({ id: "group:" + g, name: (w.groups.indexOf(g) >= 0 ? "✓ " : "") + g })))
            o.push({ id: "newgroup", name: "+ New group" })
            o.push({ id: "hide", name: "Hide this channel" })
            return o
        }
        if (kind === "playlist") {
            return [{ id: "rename", name: "Rename" }, { id: "quick", name: w.quick ? "✓ Bookmark list" : "Make bookmark list" }, { id: "delete", name: "Delete…" }]
        }
        if (kind === "unsub") return [{ id: "unsub", name: "Unsubscribe from " + (w.name || "this channel") }, { id: "keep", name: "Keep subscription" }]
        if (kind === "filter") return w.options
        return []
    }
    function menuChosen(id) {
        const w = menuFor
        menu.open = false
        if (!w) return
        const json = JSON.stringify(w)
        if (menuKind === "video") {
            const index = youtubeList.findIndex((v) => v.id === w.id)
            if (id === "add") { Qt.callLater(() => openMenu(menuButton, "add", w)); return }
            if (id === "remove") Library.removeFrom(arg.id, w.id)
            else if (id === "up" && index > 0) Library.moveIn(arg.id, index, index - 1)
            else if (id === "down" && index >= 0 && index < youtubeList.length - 1) Library.moveIn(arg.id, index, index + 1)
            else if (id === "watched") Library.setWatched(json, !JSON.parse(Library.mark(w.id)).done)
            else if (id === "forget") { Library.forget(w.id); Streams.loadYoutube("history", search.text) }
            else if (id === "hide") { Streams.toggleHiddenChannel(chanId(w), w.channel || ""); reload() }
            else if (id === "channel") openChannelOf(w)
            else if (id === "groups") {
                // No group yet: straight to naming the first one.
                if (groups.length === 0) startGroup(w)
                else { Qt.callLater(() => openMenu(menuButton, "videogroups", w)); return }
            }
        } else if (menuKind === "videogroups") {
            if (id.indexOf("group:") === 0) {
                // Into a group subscribes too: a group holds one's channels.
                if (!channels.some((c) => c.id === chanId(w))) Streams.toggleChannel(chanId(w), w.channel || "")
                Streams.toggleChannelGroup(chanId(w), id.slice(6))
            } else if (id === "newgroup") startGroup(w)
        } else if (menuKind === "add") {
            if (id === "new") {
                const pid = Library.create("Playlist " + (playlists.length + 1))
                if (pid) Library.addTo(pid, json)
            } else if (id.indexOf("to:") === 0) {
                const pid = id.slice(3)
                if (JSON.parse(Library.mark(w.id)).lists.indexOf(pid) >= 0) Library.removeFrom(pid, w.id)
                else Library.addTo(pid, json)
            }
        } else if (menuKind === "twitch") {
            if (id === "recordings") openRecordings(w)
            else if (id === "alert") Streams.toggleAlert(w.login)
        } else if (menuKind === "channel") {
            if (id === "sub") Streams.toggleChannel(w.id, w.name)
            else if (id.indexOf("group:") === 0) Streams.toggleChannelGroup(w.id, id.slice(6))
            else if (id === "newgroup") { groupFor = w; newGroup.text = ""; newGroup.focusInput() }
            else if (id === "hide") Streams.toggleHiddenChannel(w.id, w.name)
        } else if (menuKind === "playlist") {
            if (id === "rename") { renaming = true; renameField.text = w.name; renameField.focusInput() }
            else if (id === "quick") Library.makeQuick(w.id)
            else if (id === "delete") deleting = true
        } else if (menuKind === "unsub") {
            if (id === "unsub") Streams.toggleChannel(w.id, w.name)
        } else if (menuKind === "filter") {
            w.choose(id)
        }
    }
    property Item menuButton: null
    /// The star beside a video or channel: subscribes at once, asks before
    /// unsubscribing (MN: one click took a channel off every tile).
    function starChannel(button, id, name) {
        if (channels.some((c) => c.id === id && !c.freetube)) openMenu(button, "unsub", { id: id, name: name || "" })
        else Streams.toggleChannel(id, name || "")
    }
    property var groupFor: null
    /// Names a new group for a video's channel (subscribed on Add).
    function startGroup(w) {
        groupFor = { id: chanId(w), name: w.channel || "", groups: [], subscribe: true }
        newGroup.text = ""
        newGroup.focusInput()
    }
    property bool renaming: false
    property bool deleting: false
    property bool naming: false
    /// The open playlist as the library has it now.
    readonly property var openList: arg && ytView === "playlist" ? (playlists.find((p) => p.id === arg.id) || null) : null
    Connections {
        target: Library
        // An open playlist follows its changes.
        function onListsRevisionChanged() { if (!panel.onTwitch && !panel.onJelly && panel.ytView === "playlist" && panel.arg) Streams.loadYoutube("playlist", panel.arg.id) }
    }
    Connections {
        target: Streams
        function onLiveNewCountChanged() { if (panel.visible && panel.onTwitch && (panel.twView === "following" || panel.twView === "favourites")) Streams.seenNews() }
    }
    /// When the shown list was loaded, for the button above it ("As of
    /// 12:14", "As of 15 Nov 12:14"; MN, 2026-11-16).
    property real jfAsOf: 0
    Connections {
        target: Jellyfin
        function onStateChanged() { if (Jellyfin.state === "ready") panel.jfAsOf = Date.now() / 1000 }
    }
    readonly property bool listLoading: onJelly ? Jellyfin.state === "loading" : onTwitch ? Streams.twitchState === "loading" : Streams.youtubeState === "loading"
    readonly property real asOf: onJelly ? jfAsOf : onTwitch ? Streams.twitchAsOf : Streams.youtubeAsOf
    function asOfText(secs) {
        if (!(secs > 0)) return ""
        const d = new Date(secs * 1000)
        const now = new Date()
        const pad = (n) => (n < 10 ? "0" : "") + n
        const time = pad(d.getHours()) + ":" + pad(d.getMinutes())
        if (d.toDateString() === now.toDateString()) return time
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return d.getDate() + " " + months[d.getMonth()] + " " + time
    }
    function loadAgain() { if (!onJelly) Streams.forget(); reload() }
    function since(iso) {
        if (!iso) return ""
        const m = Math.round((Date.now() - Date.parse(iso)) / 60000)
        if (!(m >= 0)) return ""
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    Column {
        width: parent.width
        spacing: 10

        // Twitch / YouTube / Jellyfin; back, forth, tiles or rows.
        Item {
            id: topRow
            width: parent.width
            height: 30
            Row {
                id: siteTabs
                spacing: 18
                height: 30
                SiteTab { name: "twitch"; label: "Twitch" }
                SiteTab { name: "youtube"; label: "YouTube" }
                SiteTab { name: "jellyfin"; label: "Jellyfin" }
            }
            // The reload and sort buttons' words, as long as they fit beside
            // the tabs: "As of 12:14" and "Sort: Newest first", then "12:14",
            // then "Newest first", then the reload icon alone.
            readonly property string reloadWords: panel.listLoading ? "Loading…" : panel.asOf > 0 ? "As of " + panel.asOfText(panel.asOf) : "Load again"
            readonly property string reloadShort: panel.listLoading || !(panel.asOf > 0) ? "" : panel.asOfText(panel.asOf)
            readonly property string sortWords: "Sort: " + panel.ytSortName + " ▾"
            readonly property string sortShort: panel.ytSortName + " ▾"
            /// Room for both buttons' texts (each chip's frame and the
            /// reload icon counted).
            readonly property real room: width - siteTabs.implicitWidth - (rightRow.implicitWidth - reloadChip.implicitWidth - (ytSortChip.visible ? ytSortChip.implicitWidth : 0))
                - 16 - 30 - (ytSortChip.visible ? 18 : 0)
            readonly property real sortLongW: ytSortChip.visible ? sortLong.advanceWidth : 0
            readonly property real sortShortW: ytSortChip.visible ? sortBrief.advanceWidth : 0
            /// 0 both in full, 1 the time and the sort in full, 2 both short,
            /// 3 the icon and the sort short.
            readonly property int fit: (reloadLong.advanceWidth + 6) + sortLongW <= room ? 0
                : (reloadBrief.advanceWidth + 6) + sortLongW <= room ? 1
                : (reloadBrief.advanceWidth + 6) + sortShortW <= room ? 2 : 3
            TextMetrics { id: reloadLong; font: reloadChip.textFont; text: topRow.reloadWords.toUpperCase() }
            TextMetrics { id: reloadBrief; font: reloadChip.textFont; text: topRow.reloadShort.toUpperCase() }
            TextMetrics { id: sortLong; font: reloadChip.textFont; text: topRow.sortWords.toUpperCase() }
            TextMetrics { id: sortBrief; font: reloadChip.textFont; text: topRow.sortShort.toUpperCase() }
            Row {
                id: rightRow
                anchors.right: parent.right
                anchors.rightMargin: -6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                // Load again, with when the list is from (MN, 2026-11-16:
                // the footer's small ↻ moved up as a real button).
                Chip {
                    id: reloadChip
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "refresh"
                    text: topRow.fit === 0 ? topRow.reloadWords : topRow.fit < 3 ? topRow.reloadShort : ""
                    onClicked: panel.loadAgain()
                }
                Item { width: 8; height: 1 }
                // The list's order (MN, 0.8.43).
                Chip {
                    id: ytSortChip
                    visible: panel.ytSortOptions.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: topRow.fit < 2 ? topRow.sortWords : topRow.sortShort
                    onClicked: {
                        const view = panel.ytView
                        panel.openMenu(ytSortChip, "filter", { options: panel.ytSortOptions.map((o) => ({ id: o.id, name: (o.id === panel.ytSort ? "✓ " : "") + o.name })),
                                                              choose: (id) => { Streams.setSort(view, id); if (view === "game") panel.reload() } })
                    }
                }
                Item { visible: ytSortChip.visible; width: 8; height: 1 }
                IconButton {
                    icon: "back"
                    iconSize: 16
                    color: panel.canBack ? Theme.muted() : Theme.track
                    hoverColor: panel.canBack ? Theme.accent : Theme.track
                    tip: "Back (Alt+Left, the mouse's back button)"
                    onClicked: panel.back()
                }
                IconButton {
                    icon: "forward"
                    iconSize: 16
                    color: panel.canForward ? Theme.muted() : Theme.track
                    hoverColor: panel.canForward ? Theme.accent : Theme.track
                    tip: "Forward (Alt+Right, the mouse's forward button)"
                    onClicked: panel.forward()
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 16; color: Theme.divider }
                IconButton {
                    icon: "grid"
                    iconSize: 14
                    color: panel.tiles ? Theme.accent : Theme.muted()
                    tip: "Tiles side by side"
                    onClicked: Streams.saveGrid(true)
                }
                IconButton {
                    icon: "list"
                    iconSize: 14
                    color: !panel.tiles ? Theme.accent : Theme.muted()
                    tip: "Rows"
                    onClicked: Streams.saveGrid(false)
                }
            }
        }

        // Jellyfin: the home network, or signing in.
        Rectangle {
            visible: panel.onJelly
            width: parent.width
            height: panel.jfAccount ? 36 : signInColumn.implicitHeight + 24
            color: Qt.rgba(1, 1, 1, 0.04)
            Rectangle { width: 2; height: parent.height; color: panel.jfAccount ? Theme.accent : Theme.track }
            Row {
                visible: !!panel.jfAccount
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7
                    color: Jellyfin.state === "failed" ? Theme.track : Theme.accent
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - homeOnly.implicitWidth - 37
                    elide: Text.ElideRight
                    text: panel.jfAccount ? "Home network · " + panel.jfAccount.serverName + " · " + panel.jfAccount.user : ""
                    color: "#d8d4e0"
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: homeOnly
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HOME ONLY"
                    color: Theme.dim()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
            }
            Column {
                id: signInColumn
                visible: !panel.jfAccount
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: "SIGN IN TO YOUR JELLYFIN SERVER"
                    color: Theme.text()
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                JellyfinSignIn { id: signIn; width: parent.width }
            }
        }

        // The game's preset, in purple (not over one's own lists).
        Rectangle {
            visible: panel.gameRunning && !panel.onJelly && (panel.onTwitch || ["playlists", "playlist", "history"].indexOf(panel.ytView) < 0)
            width: parent.width
            height: panel.editingGame ? gameEdit.implicitHeight + 20 : 44
            color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.14)
            Rectangle { width: 2; height: parent.height; color: Theme.purple }
            Row {
                visible: !panel.editingGame
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: gameTag.implicitWidth + 16
                    height: 20
                    color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.35)
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: gameTag
                        anchors.centerIn: parent
                        text: panel.game.name.toUpperCase()
                        color: "#e6dbfa"
                        font.family: Theme.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - gameTag.implicitWidth - changeGame.width - 46
                    elide: Text.ElideRight
                    text: panel.onTwitch ? "Twitch category: " + panel.game.twitch : "Preset search: “" + panel.game.youtube + "”, " + ({ relevance: "by relevance", views: "most viewed first" }[panel.ytSort] || "newest first")
                    color: "#d8d4e0"
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Rectangle {
                    id: changeGame
                    anchors.verticalCenter: parent.verticalCenter
                    width: changeText.implicitWidth + 16
                    height: 28
                    color: changeMouse.containsMouse ? Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.2) : "transparent"
                    border.color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.5)
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: changeText
                        anchors.centerIn: parent
                        text: "CHANGE"
                        color: "#e6dbfa"
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    MouseArea {
                        id: changeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            gameName.text = panel.game.name
                            gameTwitch.text = panel.game.twitch
                            gameYoutube.text = panel.game.youtube
                            panel.editingGame = true
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Change the game's preset"
                }
            }
            Column {
                id: gameEdit
                visible: panel.editingGame
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 6
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: "Until games are found by themselves, set the one you play here."
                    color: "#d8d4e0"
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Field { id: gameName; width: parent.width; placeholder: "Game, e.g. AION 2" }
                Field { id: gameTwitch; width: parent.width; placeholder: "Twitch category, as Twitch names it" }
                Field { id: gameYoutube; width: parent.width; placeholder: "YouTube search words" }
                Row {
                    spacing: 8
                    TextButton {
                        text: "Save"
                        onClicked: {
                            Streams.changeGame(gameName.text, gameTwitch.text, gameYoutube.text)
                            panel.editingGame = false
                            panel.reload()
                        }
                    }
                    TextButton { text: "Cancel"; onClicked: panel.editingGame = false }
                }
            }
        }

        // The lists
        Item {
            visible: !panel.onJelly || !!panel.jfAccount
            width: parent.width
            height: 36
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            TabStrip {
                visible: panel.onTwitch
                ListTab { name: "game"; visible: panel.gameRunning; label: panel.game.name; purple: true; twitch: true; also: ["category"] }
                ListTab { name: "following"; label: "Following"; twitch: true; count: Streams.liveNewCount }
                ListTab { name: "favourites"; label: "Favorites"; twitch: true }
                ListTab { name: "categories"; label: "Categories"; twitch: true; also: panel.gameRunning ? [] : ["category"] }
                ListTab { name: "live"; label: "All live"; twitch: true }
                ListTab { name: "search"; label: ""; searchIcon: true; twitch: true; also: ["recordings"] }
            }
            Row {
                visible: panel.onJelly
                height: parent.height
                spacing: 16
                ListTab { name: "continue"; label: "Continue"; site: "jellyfin" }
                ListTab { name: "nextup"; label: "Next up"; site: "jellyfin" }
                ListTab { name: "libraries"; label: "Libraries"; site: "jellyfin" }
                ListTab { name: "search"; label: ""; searchIcon: true; site: "jellyfin" }
            }
            TabStrip {
                visible: Streams.tab === "youtube"
                ListTab { name: "game"; visible: panel.gameRunning; label: panel.game.name; purple: true }
                ListTab { name: "subscriptions"; label: "Subscriptions" }
                ListTab { name: "trending"; label: "Trending" }
                ListTab { name: "playlists"; label: "Playlists"; also: ["playlist"] }
                ListTab { name: "history"; label: "History" }
                ListTab { name: "channels"; label: "Channels"; also: ["channel"] }
                ListTab { name: "search"; label: ""; searchIcon: true }
            }
        }

        // Search
        Rectangle {
            visible: panel.searchShown
            width: parent.width
            height: 36
            color: "#1b1a20"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: search.activeFocus ? Theme.accent : "#3a3842" }
            HudIcon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 15
                lineWidth: 2
                color: Theme.dim()
            }
            TextInput {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text()
                selectionColor: Theme.accent
                selectedTextColor: "#0c0c0f"
                font.family: Theme.body
                font.pixelSize: 13
                clip: true
                maximumLength: 100
                onAccepted: panel.runSearch()
                // The history narrows as one types (it is here already).
                onTextChanged: if (!panel.onTwitch && !panel.onJelly && panel.ytView === "history" && panel.visible) Streams.loadYoutube("history", text)
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: search.text.length === 0
                    text: panel.onJelly ? "A film, a show or an episode, then Enter"
                        : panel.onTwitch ? (panel.twView === "categories" ? "A game or category, then Enter" : "A channel's name, then Enter")
                        : panel.ytView === "history" ? "Search what you watched"
                        : panel.ytView === "playlists" ? "Search playlists"
                        : "Search words or a video's link, then Enter"
                    color: Theme.dim()
                    font: search.font
                }
                Accessible.name: panel.onJelly ? "Search Jellyfin" : panel.onTwitch ? "Search Twitch" : "Search YouTube"
            }
        }

        // YouTube's Trending: Gaming, and football by competition.
        Flow {
            visible: !panel.onTwitch && !panel.onJelly && panel.ytView === "trending"
            width: parent.width
            spacing: 6
            Chip { text: "Gaming"; on: Streams.trendSection === "gaming"; onClicked: panel.go({ tab: "youtube", view: "trending", text: "gaming", channel: null }) }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 24; verticalAlignment: Text.AlignVCenter; leftPadding: 8; rightPadding: 2
                text: "FOOTBALL"; color: Theme.dim(); font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
            Repeater {
                model: [["europe", "Europe"], ["national", "National teams"], ["tr", "Süper Lig"], ["de", "Bundesliga"], ["en", "Premier League"],
                        ["fr", "Ligue 1"], ["it", "Serie A"], ["es", "LaLiga"], ["bjk", "Beşiktaş"]]
                delegate: Chip {
                    required property var modelData
                    text: modelData[1]
                    on: Streams.trendSection === modelData[0]
                    onClicked: panel.go({ tab: "youtube", view: "trending", text: modelData[0], channel: null })
                }
            }
            // The person's own searches (Settings → Streams → YouTube).
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: mySearches.count > 0
                height: 24; verticalAlignment: Text.AlignVCenter; leftPadding: 8; rightPadding: 2
                text: "MINE"; color: Theme.dim(); font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
            Repeater {
                id: mySearches
                model: JSON.parse(Streams.trendCustom)
                delegate: Chip {
                    required property var modelData
                    text: modelData.name
                    on: Streams.trendSection === modelData.id
                    onClicked: panel.go({ tab: "youtube", view: "trending", text: modelData.id, channel: null })
                }
            }
        }

        // Subscriptions and channels: one group of them, or all. Shown
        // without groups too, saying how to make one (MN couldn't find them).
        Flow {
            visible: !panel.onTwitch && !panel.onJelly && (panel.ytView === "subscriptions" || panel.ytView === "channels")
            width: parent.width
            spacing: 6
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 24; verticalAlignment: Text.AlignVCenter; rightPadding: 2
                text: "GROUPS"; color: Theme.dim(); font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
            Chip { text: "All"; on: !Streams.group; onClicked: { Streams.chooseGroup(""); panel.reload() } }
            Repeater {
                model: panel.groups
                delegate: Chip {
                    required property string modelData
                    text: modelData
                    on: Streams.group === modelData
                    onClicked: { Streams.chooseGroup(modelData); if (panel.ytView === "subscriptions") panel.reload() }
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 24; verticalAlignment: Text.AlignVCenter; leftPadding: 4
                text: panel.groups.length === 0 ? "None yet: ⋯ beside a channel or a video → + New group" : "⋯ beside a channel or a video sorts it in"
                color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11 }
        }

        // A new group for a channel (from its menu).
        Row {
            visible: panel.groupFor !== null
            width: parent.width
            spacing: 8
            Field { id: newGroup; width: parent.width - groupOk.width - groupCancel.width - 16; placeholder: "New group for " + (panel.groupFor ? panel.groupFor.name : ""); onAccepted: groupOk.clicked() }
            TextButton { id: groupOk; text: "Add"; onClicked: {
                const c = panel.groupFor
                if (newGroup.text.trim()) {
                    if (c.subscribe && !panel.channels.some((x) => x.id === c.id)) Streams.toggleChannel(c.id, c.name)
                    Streams.toggleChannelGroup(c.id, newGroup.text)
                }
                panel.groupFor = null
            } }
            TextButton { id: groupCancel; text: "Cancel"; onClicked: panel.groupFor = null }
        }

        // YouTube's search: sort, when, how long.
        Flow {
            visible: !panel.onTwitch && !panel.onJelly && panel.ytView === "search"
            width: parent.width
            spacing: 6
            FilterChip {
                key: "sort"; label: "Sort"
                options: [{ id: "relevance", name: "Relevance" }, { id: "date", name: "Newest" }, { id: "views", name: "Most viewed" }]
                current: panel.searchFilter.sort
            }
            FilterChip {
                key: "date"; label: "Uploaded"
                options: [{ id: "any", name: "Any time" }, { id: "today", name: "Today" }, { id: "week", name: "This week" }, { id: "month", name: "This month" }, { id: "year", name: "This year" }]
                current: panel.searchFilter.date
            }
            FilterChip {
                key: "length"; label: "Length"
                options: [{ id: "any", name: "Any" }, { id: "short", name: "Under 4 min" }, { id: "medium", name: "4 to 20 min" }, { id: "long", name: "Over 20 min" }]
                current: panel.searchFilter.length
            }
        }

        // The playlists: sort, search in their videos too, a new one.
        Item {
            visible: !panel.onTwitch && !panel.onJelly && panel.ytView === "playlists"
            width: parent.width
            height: panel.naming ? 32 : 24
            Row {
                visible: !panel.naming
                spacing: 6
                Chip {
                    id: sortChip
                    readonly property var names: ({ played: "Last played", created: "Newest", updated: "Last changed", az: "A to Z", za: "Z to A" })
                    text: "Sort: " + names[panel.playlistSort]
                    onClicked: panel.openMenu(sortChip, "filter", { options: Object.keys(names).map((k) => ({ id: k, name: names[k] })), choose: (id) => panel.playlistSort = id })
                }
                Chip { text: "Search in videos"; on: panel.matchVideos; onClicked: panel.matchVideos = !panel.matchVideos }
            }
            Chip {
                visible: !panel.naming
                anchors.right: parent.right
                text: "+ New playlist"
                on: true
                onClicked: { panel.naming = true; newList.text = ""; newList.focusInput() }
            }
            Row {
                visible: panel.naming
                width: parent.width
                spacing: 8
                Field { id: newList; width: parent.width - listOk.width - listCancel.width - 16; placeholder: "The new playlist's name"; onAccepted: listOk.clicked() }
                TextButton { id: listOk; height: 32; text: "Create"; onClicked: { if (newList.text.trim()) Library.create(newList.text); panel.naming = false } }
                TextButton { id: listCancel; height: 32; text: "Cancel"; onClicked: panel.naming = false }
            }
        }

        // An open playlist: back, its name, play all, shuffle, loop.
        Item {
            visible: !panel.onTwitch && !panel.onJelly && panel.ytView === "playlist" && panel.arg !== null
            width: parent.width
            height: panel.renaming || panel.deleting ? 34 : 28
            Row {
                visible: !panel.renaming && !panel.deleting
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                TextButton { height: 28; text: "‹ Playlists"; onClicked: panel.go({ tab: "youtube", view: "playlists", text: "", channel: null }) }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, panel.width - 380)
                    elide: Text.ElideRight
                    text: panel.openList ? panel.openList.name : (panel.arg ? panel.arg.name : "")
                    color: Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
                HudIcon {
                    visible: !!panel.openList && panel.openList.quick
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bookmark"; size: 13; lineWidth: 2.2; filled: true; color: Theme.accent
                }
            }
            Row {
                visible: !panel.renaming && !panel.deleting
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                IconButton { icon: "play"; iconSize: 14; color: Theme.accent; tip: "Play all"; onClicked: panel.playAll(false) }
                IconButton { icon: "shuffle"; iconSize: 15; color: Theme.muted(); tip: "Play all, shuffled"; onClicked: panel.playAll(true) }
                IconButton { icon: "loop"; iconSize: 15; color: panel.loopList ? Theme.accent : Theme.muted(); tip: panel.loopList ? "Loop: on" : "Loop: off"; onClicked: panel.loopList = !panel.loopList }
                IconButton { id: listMore; icon: "more"; iconSize: 15; color: Theme.muted(); tip: "Rename, bookmark list, delete"; onClicked: if (panel.openList) panel.openMenu(listMore, "playlist", panel.openList) }
            }
            Row {
                visible: panel.renaming
                width: parent.width
                spacing: 8
                Field { id: renameField; width: parent.width - renameOk.width - renameCancel.width - 16; placeholder: "Name"; onAccepted: renameOk.clicked() }
                TextButton { id: renameOk; height: 32; text: "Rename"; onClicked: { Library.rename(panel.arg.id, renameField.text); panel.renaming = false } }
                TextButton { id: renameCancel; height: 32; text: "Cancel"; onClicked: panel.renaming = false }
            }
            Row {
                visible: panel.deleting
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Delete “" + (panel.arg ? panel.arg.name : "") + "”?"
                    color: Theme.text(); font.family: Theme.body; font.pixelSize: 13 }
                TextButton { height: 30; text: "Delete"; danger: true; onClicked: { Library.removePlaylist(panel.arg.id); panel.deleting = false; panel.go({ tab: "youtube", view: "playlists", text: "", channel: null }) } }
                TextButton { height: 30; text: "Keep"; onClicked: panel.deleting = false }
            }
        }

        // The history: leave watched videos out of the lists, clear it.
        Item {
            visible: !panel.onTwitch && !panel.onJelly && panel.ytView === "history"
            width: parent.width
            height: 24
            Chip { text: "Hide watched in lists"; on: panel.filters.watched; onClicked: Streams.setHideWatched(!panel.filters.watched) }
            Row {
                anchors.right: parent.right
                spacing: 6
                Chip { id: clearChip; property bool sure: false; text: sure ? "Really clear?" : "Clear history"; on: sure
                    onClicked: { if (sure) { Library.clearHistory(); Streams.loadYoutube("history", ""); sure = false } else { sure = true; clearAgain.restart() } }
                    Timer { id: clearAgain; interval: 4000; onTriggered: clearChip.sure = false }
                }
            }
        }

        // Twitch: who went live since the last look (live notes on).
        Column {
            visible: panel.onTwitch && Streams.alerts && panel.liveNews.length > 0 && (panel.twView === "following" || panel.twView === "favourites" || panel.twView === "game")
            width: parent.width
            spacing: 2
            Repeater {
                model: panel.liveNews.slice(0, 3)
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 30
                    color: newsMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)
                    Rectangle { width: 2; height: parent.height; color: Theme.red }
                    Row {
                        x: 12
                        width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; color: Theme.red }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 60
                            elide: Text.ElideRight
                            text: "<b>" + modelData.name + "</b> went live" + (modelData.game ? " · " + modelData.game : "") + (modelData.title ? " · " + modelData.title : "")
                            textFormat: Text.StyledText
                            color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 12 }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            anchors.verticalCenter: parent.verticalCenter
                            text: "WATCH"; color: Theme.accent; font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                    }
                    MouseArea { id: newsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.playTwitch({ login: modelData.login, name: modelData.name, game: modelData.game, title: modelData.title }) }
                }
            }
        }

        // Twitch's live lists: order, reruns, languages.
        Flow {
            visible: panel.onTwitch && (panel.twView === "game" || panel.twView === "live" || panel.twView === "category")
            width: parent.width
            spacing: 6
            Chip {
                id: twSort
                text: panel.twitchFilter.sort === "new" ? "Sort: Just started" : "Sort: Most viewers"
                onClicked: panel.openMenu(twSort, "filter", { options: [{ id: "viewers", name: "Most viewers" }, { id: "new", name: "Just started" }],
                                                               choose: (id) => { Streams.changeTwitchFilter("sort", id); panel.reload() } })
            }
            Chip {
                id: twLang
                readonly property var sets: [["", "All languages"], ["de", "German"], ["en", "English"], ["tr", "Turkish"], ["de,en", "German + English"], ["de,en,tr", "German, English, Turkish"]]
                readonly property string now: panel.twitchFilter.languages.join(",")
                text: { const f = sets.find((x) => x[0] === now); return f ? f[1] : now.toUpperCase() }
                on: now.length > 0
                onClicked: panel.openMenu(twLang, "filter", { options: sets.map((x) => ({ id: x[0] || "all", name: x[1] })),
                                                               choose: (id) => { Streams.changeTwitchFilter("languages", id === "all" ? "" : id); panel.reload() } })
            }
            Chip { text: "No reruns"; on: panel.twitchFilter.reruns; onClicked: { Streams.changeTwitchFilter("reruns", panel.twitchFilter.reruns ? "off" : "on"); panel.reload() } }
        }

        // A Twitch category or a channel's recordings: the way back.
        Row {
            visible: panel.onTwitch && (panel.twView === "category" || panel.twView === "recordings") && panel.arg !== null
            spacing: 10
            TextButton { height: 28; text: panel.twView === "category" ? "‹ Categories" : "‹ Back"
                onClicked: panel.twView === "category" ? panel.go({ tab: "twitch", view: "categories", text: "", channel: null }) : panel.back() }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                text: panel.arg ? (panel.twView === "category" ? panel.arg.title : panel.arg.name + " · past broadcasts and clips") : ""
                color: Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
        }

        // Jellyfin: where in the libraries (a click goes back there).
        Flow {
            visible: panel.onJelly && Jellyfin.view === "folder" && panel.jfPath.length > 0
            width: parent.width
            spacing: 6
            TextButton { text: "‹ Libraries"; onClicked: panel.go({ tab: "jellyfin", view: "libraries", text: "", channel: null, path: [] }) }
            Repeater {
                model: panel.jfPath
                delegate: Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    required property var modelData
                    required property int index
                    readonly property bool last: index === panel.jfPath.length - 1
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: "/  " + modelData.name
                    color: last ? Theme.text() : (crumbMouse.containsMouse ? Theme.accent : Theme.muted())
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: last ? Font.DemiBold : Font.Normal
                    MouseArea {
                        id: crumbMouse
                        anchors.fill: parent
                        enabled: !parent.last
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.go({ tab: "jellyfin", view: "folder", text: "", channel: null, path: panel.jfPath.slice(0, parent.index + 1) })
                    }
                }
            }
        }

        // The channel whose videos show (My channels → one).
        Row {
            visible: Streams.tab === "youtube" && Streams.youtubeView === "channel" && panel.channel !== null
            spacing: 10
            TextButton { text: "‹ Channels"; onClicked: panel.go({ tab: "youtube", view: "channels", text: "", channel: null }) }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: panel.channel ? panel.channel.name : ""
                color: Theme.text()
                font.family: Theme.body
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Item {
            id: listArea
            visible: !panel.onJelly || !!panel.jfAccount
            x: -14
            width: parent.width + 28
            // Rows: four; tiles: two rows of them.
            height: (panel.tiles && !panel.channelsView ? Math.max(79 * 4, Math.min(grid.cellHeight * 2, 79 * 5)) : 79 * 4) + panel.grow
            clip: true
            readonly property int columns: panel.listKind === "categories" ? Math.max(3, Math.min(7, Math.floor((width - 16) / 120)))
                : Math.max(2, Math.min(4, Math.floor((width - 16) / 230)))
            readonly property int channelColumns: Math.max(2, Math.min(5, Math.floor((width - 16) / 190)))
            readonly property Flickable shown: panel.channelsView ? (panel.tiles ? channelGrid : channelList) : (panel.tiles ? grid : list)
            // The mouse's back and forward buttons.
            TapHandler {
                acceptedButtons: Qt.BackButton | Qt.ForwardButton
                onTapped: (point, button) => button === Qt.BackButton ? panel.back() : panel.forward()
            }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !panel.channelsView && !panel.tiles
                model: visible ? panel.listModel : []
                delegate: ({ jelly: jellyRow, twitch: twitchRow, categories: categoryRow, recordings: recordingRow, playlists: playlistRow, video: videoRow })[panel.listKind] || videoRow
                onAtYEndChanged: if (atYEnd) panel.moreAtEnd()
                footer: moreFooter
                // Rows made a little ahead: no hitch while the wheel moves on.
                cacheBuffer: 600
            }
            GridView {
                id: grid
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !panel.channelsView && panel.tiles
                cellWidth: Math.floor(width / listArea.columns)
                cellHeight: panel.listKind === "categories" ? Math.round((cellWidth - 12) * 4 / 3) + 50
                    : Math.round((cellWidth - 12) * 9 / 16) + (panel.onJelly || panel.listKind === "playlists" ? 58 : 78)
                model: visible ? panel.listModel : []
                delegate: ({ jelly: jellyTile, twitch: twitchTile, categories: categoryTile, recordings: recordingTile, playlists: playlistTile, video: videoTile })[panel.listKind] || videoTile
                onAtYEndChanged: if (atYEnd) panel.moreAtEnd()
                footer: moreFooter
                // Rows made a little ahead: no hitch while the wheel moves on.
                cacheBuffer: 600
            }
            ListView {
                id: channelList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: panel.channelsView && !panel.tiles
                model: visible ? panel.channelModel : []
                delegate: channelRow
            }
            GridView {
                id: channelGrid
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: panel.channelsView && panel.tiles
                cellWidth: Math.floor(width / listArea.channelColumns)
                cellHeight: 72
                model: visible ? panel.channelModel : []
                delegate: channelTile
            }
            WheelScroll { id: listWheel; flick: list; step: 79 * 2 }
            WheelScroll { id: gridWheel; flick: grid; step: grid.cellHeight }
            WheelScroll { id: channelListWheel; flick: channelList; step: 58 * 3 }
            WheelScroll { id: channelGridWheel; flick: channelGrid; step: 72 * 2 }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.centerIn: parent
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                readonly property string st: panel.onJelly ? Jellyfin.state : panel.onTwitch ? Streams.twitchState : panel.listKind === "playlists" ? "ready" : Streams.youtubeState
                readonly property int count: listArea.shown.count
                visible: (st === "loading" && count === 0) || st === "failed" || (st !== "loading" && count === 0)
                text: st === "loading" ? "Loading…"
                    : st === "failed" ? (panel.onJelly ? Jellyfin.message : panel.onTwitch ? Streams.twitchMessage : Streams.youtubeMessage)
                    : panel.onJelly ? (Jellyfin.view === "search" ? "Type, then Enter."
                        : Jellyfin.view === "continue" ? "Nothing half watched right now."
                        : Jellyfin.view === "nextup" ? "No next episodes right now."
                        : st === "idle" ? "" : "Nothing in here.")
                    : panel.channelsView ? (Streams.group ? "No channels in this group yet: a channel's menu (⋯) puts it in one." : "No channels yet: subscribe with the star beside a video, or take over FreeTube's in Settings → Streams.")
                    : panel.listKind === "playlists" ? (panel.playlists.length === 0 ? "No playlists yet: + New playlist, or the bookmark beside a video starts “Watch later”." : "No playlist matches.")
                    : !panel.onTwitch && panel.ytView === "playlist" ? "Nothing in here yet: a video's menu (⋯) adds it."
                    : !panel.onTwitch && panel.ytView === "history" ? (search.text ? "Nothing watched matches." : "Nothing watched yet.")
                    : panel.onTwitch && Streams.twitchView === "recordings" ? "No past broadcasts or clips."
                    : (panel.onTwitch ? Streams.twitchView : Streams.youtubeView) === "search" ? "Type, then Enter."
                    : panel.onTwitch && Streams.twitchView === "favourites" ? "No favorites yet: the star beside a channel keeps it."
                    : panel.onTwitch && Streams.twitchView === "following" ? "You follow no channels yet."
                    : st === "idle" ? "" : "Nothing here right now."
                color: st === "failed" ? Theme.red : Theme.dim()
                font.family: Theme.body
                font.pixelSize: 12
            }
        }

        // What it goes through
        Item {
            x: -14
            width: parent.width + 28
            height: 30
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: Theme.accent }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.onJelly ? "Your own server, in your home network only · nothing goes out"
                        : panel.onTwitch
                        ? (panel.account.streamlink ? "Ad-free via Streamlink" : "Through yt-dlp (install streamlink for no ad breaks)")
                          + (panel.account.user && panel.account.user !== "?" && panel.account.user !== "…" ? " · signed in as " + panel.account.user : "")
                        : panel.ytView === "playlists" || panel.ytView === "playlist" || panel.ytView === "history" ? "Kept on this computer only · nothing goes out"
                        : (Streams.freetubeLive ? "Subscriptions read from FreeTube" : "Your subscriptions") + " · search via yt-dlp"
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
        }
    }

    // Screenshots (GC_DEMO=…,more): the list's end with its button.
    Timer {
        running: nativeWindow.demo.indexOf("more") >= 0
        interval: 300
        onTriggered: listArea.shown.positionViewAtEnd()
    }
    // Scrolled to the end of a list: its next page, where there is one.
    function moreAtEnd() {
        if (onJelly && Jellyfin.hasMore) Jellyfin.more()
        else if (onTwitch && Streams.twitchHasMore) Streams.loadMoreTwitch()
        else if (!onTwitch && !onJelly && Streams.youtubeHasMore) Streams.loadMoreYoutube()
    }
    // Under a Twitch list with more: a button (it also comes on its own
    // when scrolled to the end).
    Component {
        id: moreFooter
        Item {
            readonly property bool yt: !panel.onTwitch && !panel.onJelly
            readonly property bool more: panel.onTwitch ? Streams.twitchHasMore : yt && Streams.youtubeHasMore
            readonly property bool loading: panel.onTwitch ? Streams.twitchLoadingMore : Streams.youtubeLoadingMore
            readonly property string note: panel.onTwitch ? Streams.twitchMoreNote : yt ? Streams.youtubeMoreNote : ""
            readonly property bool shown: more || note.length > 0
            width: ListView.view ? ListView.view.width : GridView.view ? GridView.view.width : 0
            height: shown ? (note.length > 0 ? 76 : 52) : 0
            visible: shown
            Column {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 6
                TextButton {
                    visible: parent.parent.more
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitHeight: 30
                    text: parent.parent.loading ? "Loading…" : "Load more"
                    onClicked: if (!parent.parent.loading) panel.moreAtEnd()
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: parent.parent.note.length > 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: parent.parent.note
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
        }
    }

    // The menu beside a video, a channel or a playlist (one, moved there).
    Picker {
        id: menu
        parent: panel
        z: 50
        // "Unsubscribe from <channel>" wants room for the name.
        width: panel.menuKind === "unsub" ? 320 : 220
        maxHeight: 260
        current: ""
        onChosen: (id) => panel.menuChosen(id)
    }
    // A click elsewhere closes the menu.
    MouseArea {
        parent: panel
        anchors.fill: parent
        z: 49
        visible: menu.open
        onClicked: menu.open = false
    }

    Component {
        id: twitchRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            readonly property bool current: panel.playingTwitch === modelData.login
            readonly property bool fav: panel.favs.indexOf((modelData.login || "").toLowerCase()) >= 0
            Rectangle {
                anchors.fill: parent
                color: row.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
            }
            Rectangle { visible: row.current; width: 2; height: parent.height; color: Theme.accent }
            Rectangle { visible: !row.current; anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.modelData.live ? panel.playTwitch(row.modelData) : panel.openRecordings(row.modelData)
            }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.live ? row.modelData.picture : row.modelData.avatar
                dimmed: !row.modelData.live
                Rectangle {
                    visible: row.modelData.live
                    x: 4; y: 4
                    width: liveText.implicitWidth + 8
                    height: liveText.implicitHeight + 2
                    color: Theme.red
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow; id: liveText; anchors.centerIn: parent; text: "LIVE"; color: "#ffffff"; font.pixelSize: 9; font.weight: Font.Bold; font.family: Theme.body }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: row.current
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    text: "PLAYING"
                    color: Theme.accent
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }
            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: star.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: row.current ? Theme.accent : Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.modelData.live ? row.modelData.title : "Offline · past broadcasts and clips"
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    visible: row.modelData.live
                    text: {
                        const parts = [Number(row.modelData.viewers).toLocaleString(Qt.locale("en_US"), "f", 0) + " viewers"]
                        if (row.modelData.game && Streams.twitchView !== "game") parts.push(row.modelData.game)
                        const t = panel.since(row.modelData.since)
                        if (t) parts.push(t)
                        return parts.join(" · ")
                    }
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            Row {
                id: star
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                IconButton {
                    width: 32
                    height: 34
                    icon: "star"
                    iconSize: 16
                    filled: row.fav
                    color: row.fav ? Theme.accent : Theme.dim()
                    tip: row.fav ? "Remove from favorites" : "Add to favorites"
                    onClicked: Streams.toggleFavourite(row.modelData.login)
                }
                IconButton { id: twMore; width: 26; height: 34; icon: "more"; iconSize: 15; color: Theme.dim(); tip: "Past broadcasts and clips, live notes"
                    onClicked: panel.openMenu(twMore, "twitch", row.modelData) }
            }
        }
    }

    Component {
        id: videoRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            required property int index
            readonly property bool current: panel.playingYoutube === modelData.id
            readonly property bool kept: !!modelData.channelId && panel.channels.some((c) => c.id === panel.chanId(modelData))
            readonly property var mark: Library.revision >= 0 ? JSON.parse(Library.mark(modelData.id)) : null
            Rectangle {
                anchors.fill: parent
                color: row.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
            }
            Rectangle { visible: row.current; width: 2; height: parent.height; color: Theme.accent }
            Rectangle { visible: !row.current; anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.ytView === "playlist" ? panel.playVideo(row.modelData, panel.youtubeShown, row.index) : panel.playVideo(row.modelData)
            }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.picture
                YtProgress { mark: row.mark }
                HdrBadge { label: panel.ytHdr(row.modelData) }
                Rectangle {
                    visible: row.modelData.duration > 0 || row.modelData.live || row.modelData.upcoming
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: lengthText.implicitWidth + 8
                    height: lengthText.implicitHeight + 2
                    color: row.modelData.live ? Theme.red : Qt.rgba(0, 0, 0, 0.75)
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: lengthText
                        anchors.centerIn: parent
                        text: row.modelData.live ? "LIVE" : row.modelData.upcoming ? "UPCOMING" : panel.clock(row.modelData.duration)
                        color: Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: star.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    text: row.modelData.title
                    color: row.current ? Theme.accent : Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    lineHeight: 1.1
                }
                VideoByline {
                    width: parent.width
                    video: row.modelData
                    when: panel.seenAndWhen(row.modelData)
                    tail: row.current ? "watching" : ""
                    onOpenChannel: panel.openChannelOf(row.modelData)
                }
            }
            Row {
                id: star
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                BookmarkButton { video: row.modelData; mark: row.mark; width: 30; height: 34 }
                IconButton {
                    id: rowStar
                    visible: !!row.modelData.channelId
                    width: 30
                    height: 34
                    icon: "star"
                    iconSize: 16
                    filled: row.kept
                    color: row.kept ? Theme.accent : Theme.dim()
                    tip: row.kept ? "Unsubscribe from " + row.modelData.channel : "Subscribe to " + row.modelData.channel
                    onClicked: panel.starChannel(rowStar, panel.chanId(row.modelData), row.modelData.channel)
                }
                IconButton { id: rowMore; width: 26; height: 34; icon: "more"; iconSize: 15; color: Theme.dim(); tip: "Playlists, channel, groups, watched, hide"
                    onClicked: panel.openMenu(rowMore, "video", row.modelData) }
            }
        }
    }

    Component {
        id: channelRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 58
            Rectangle { anchors.fill: parent; color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent" }
            Rectangle { anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.go({ tab: "youtube", view: "channel", text: "", channel: row.modelData })
            }
            ChannelPicture {
                id: rowPicture
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                size: 40
                channel: row.modelData
            }
            Column {
                anchors.left: rowPicture.right
                anchors.leftMargin: 10
                anchors.right: star.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    // The whole name: two lines before it is shortened.
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 0.95
                    text: row.modelData.name
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: [row.modelData.freetube ? "From FreeTube" : "Subscribed"].concat(row.modelData.groups).join(" · ")
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            Row {
                id: star
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                IconButton {
                    id: chStar
                    width: 32
                    height: 34
                    icon: "star"
                    iconSize: 16
                    filled: !row.modelData.freetube
                    color: row.modelData.freetube ? Theme.dim() : Theme.accent
                    tip: row.modelData.freetube ? "Subscribe here (not only in FreeTube)" : "Unsubscribe"
                    onClicked: panel.starChannel(chStar, row.modelData.id, row.modelData.name)
                }
                IconButton { id: chMore; width: 26; height: 34; icon: "more"; iconSize: 15; color: Theme.dim(); tip: "Groups, hide"
                    onClicked: panel.openMenu(chMore, "channel", row.modelData) }
            }
        }
    }

    // Tiles: side by side, two to four a row as the panel is wide.
    component Tile: Item {
        id: tile
        property bool current: false
        property bool hovered: tileMouse.containsMouse
        readonly property Item thumb: tileThumb
        property string picture
        property bool dimmed: false
        default property alias extra: info.data
        signal clicked
        width: GridView.view.cellWidth
        height: GridView.view.cellHeight
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            color: tile.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (tile.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
            Rectangle { visible: tile.current; width: parent.width; height: 2; color: Theme.accent }
        }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
        Thumb {
            id: tileThumb
            source: tile.picture
            dimmed: tile.dimmed
            x: 6
            y: 6
            width: parent.width - 12
            height: Math.round(width * 9 / 16)
        }
        Item {
            id: info
            x: 6
            anchors.top: tileThumb.bottom
            anchors.topMargin: 6
            width: parent.width - 12
            anchors.bottom: parent.bottom
        }
    }

    Component {
        id: twitchTile
        Tile {
            id: tile
            required property var modelData
            current: panel.playingTwitch === modelData.login
            readonly property bool fav: panel.favs.indexOf((modelData.login || "").toLowerCase()) >= 0
            picture: (modelData.live ? modelData.picture : modelData.avatar) || ""
            dimmed: !modelData.live
            onClicked: modelData.live ? panel.playTwitch(modelData) : panel.openRecordings(modelData)
            Rectangle {
                parent: tile.thumb
                visible: tile.modelData.live
                x: 4; y: 4
                width: tileLive.implicitWidth + 8
                height: tileLive.implicitHeight + 2
                color: Theme.red
                Text { style: Theme.textStyle(); styleColor: Theme.shadow; id: tileLive; anchors.centerIn: parent; text: "LIVE"; color: "#ffffff"; font.pixelSize: 9; font.weight: Font.Bold; font.family: Theme.body }
            }
            Rectangle {
                parent: tile.thumb
                visible: tile.modelData.live
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: tileViewers.implicitWidth + 8
                height: tileViewers.implicitHeight + 2
                color: Qt.rgba(0, 0, 0, 0.75)
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: tileViewers
                    anchors.centerIn: parent
                    text: Number(tile.modelData.viewers).toLocaleString(Qt.locale("en_US"), "f", 0) + " viewers"
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                parent: tile.thumb
                visible: tile.current
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                text: "PLAYING"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                anchors.left: parent.left
                anchors.right: tileStar.left
                anchors.rightMargin: 4
                spacing: 1
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.current ? Theme.accent : Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.live ? tile.modelData.title : "Offline · past broadcasts"
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    visible: tile.modelData.live
                    text: {
                        const parts = []
                        if (tile.modelData.game && Streams.twitchView !== "game") parts.push(tile.modelData.game)
                        const t = panel.since(tile.modelData.since)
                        if (t) parts.push(t)
                        return parts.join(" · ")
                    }
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            Row {
                id: tileStar
                anchors.right: parent.right
                anchors.rightMargin: -6
                y: -6
                IconButton {
                    width: 26
                    height: 30
                    icon: "star"
                    iconSize: 15
                    filled: tile.fav
                    color: tile.fav ? Theme.accent : Theme.dim()
                    tip: tile.fav ? "Remove from favorites" : "Add to favorites"
                    onClicked: Streams.toggleFavourite(tile.modelData.login)
                }
                IconButton { id: twTileMore; width: 24; height: 30; icon: "more"; iconSize: 15; color: Theme.dim(); tip: "Past broadcasts and clips, live notes"
                    onClicked: panel.openMenu(twTileMore, "twitch", tile.modelData) }
            }
        }
    }

    Component {
        id: videoTile
        Tile {
            id: tile
            required property var modelData
            required property int index
            current: panel.playingYoutube === modelData.id
            readonly property bool kept: !!modelData.channelId && panel.channels.some((c) => c.id === panel.chanId(modelData))
            readonly property var mark: Library.revision >= 0 ? JSON.parse(Library.mark(modelData.id)) : null
            picture: modelData.picture
            onClicked: panel.ytView === "playlist" ? panel.playVideo(modelData, panel.youtubeShown, index) : panel.playVideo(modelData)
            YtProgress { parent: tile.thumb; mark: tile.mark }
            HdrBadge { parent: tile.thumb; label: panel.ytHdr(tile.modelData) }
            BookmarkButton {
                parent: tile.thumb
                visible: tile.hovered || (!!tile.mark && tile.mark.quick)
                video: tile.modelData
                mark: tile.mark
                x: 2; y: 2
                width: 28; height: 28
                Rectangle { anchors.fill: parent; z: -1; color: Qt.rgba(0, 0, 0, 0.6) }
            }
            Rectangle {
                parent: tile.thumb
                visible: tile.modelData.duration > 0 || tile.modelData.live || tile.modelData.upcoming
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: tileLength.implicitWidth + 8
                height: tileLength.implicitHeight + 2
                color: tile.modelData.live ? Theme.red : Qt.rgba(0, 0, 0, 0.75)
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: tileLength
                    anchors.centerIn: parent
                    text: tile.modelData.live ? "LIVE" : tile.modelData.upcoming ? "UPCOMING" : panel.clock(tile.modelData.duration)
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                parent: tile.thumb
                visible: tile.current
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 4
                text: "WATCHING"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                anchors.left: parent.left
                anchors.right: tileStar.left
                anchors.rightMargin: 4
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    text: tile.modelData.title
                    color: tile.current ? Theme.accent : Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    lineHeight: 1.05
                }
                VideoByline {
                    width: parent.width
                    video: tile.modelData
                    when: panel.seenAndWhen(tile.modelData)
                    onOpenChannel: panel.openChannelOf(tile.modelData)
                }
            }
            Row {
                id: tileStar
                anchors.right: parent.right
                anchors.rightMargin: -6
                y: -6
                IconButton {
                    id: tileStarButton
                    visible: !!tile.modelData.channelId
                    width: visible ? 26 : 0
                    height: 30
                    icon: "star"
                    iconSize: 15
                    filled: tile.kept
                    color: tile.kept ? Theme.accent : Theme.dim()
                    tip: tile.kept ? "Unsubscribe from " + tile.modelData.channel : "Subscribe to " + tile.modelData.channel
                    onClicked: panel.starChannel(tileStarButton, panel.chanId(tile.modelData), tile.modelData.channel)
                }
                IconButton { id: tileMore; width: 24; height: 30; icon: "more"; iconSize: 15; color: Theme.dim(); tip: "Playlists, channel, groups, watched, hide"
                    onClicked: panel.openMenu(tileMore, "video", tile.modelData) }
            }
        }
    }

    Component {
        id: channelTile
        Item {
            id: tile
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.025)
                Rectangle { width: 2; height: parent.height; color: tile.modelData.freetube ? Theme.track : Theme.accent }
            }
            MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.go({ tab: "youtube", view: "channel", text: "", channel: tile.modelData })
            }
            ChannelPicture {
                id: tilePicture
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                size: 44
                channel: tile.modelData
            }
            Column {
                anchors.left: tilePicture.right
                anchors.leftMargin: 9
                anchors.right: tileStar.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    // The whole name: two lines before it is shortened.
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 0.95
                    text: tile.modelData.name
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: [tile.modelData.freetube ? "From FreeTube" : "Subscribed"].concat(tile.modelData.groups).join(" · ")
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            IconButton {
                id: tileStar
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 30
                icon: "more"
                iconSize: 15
                color: Theme.dim()
                tip: "Groups, subscribe, hide"
                onClicked: panel.openMenu(tileStar, "channel", tile.modelData)
            }
        }
    }

    Component {
        id: jellyRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            readonly property bool current: panel.playingJellyfin === modelData.id
            Rectangle {
                anchors.fill: parent
                color: row.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
            }
            Rectangle { visible: row.current; width: 2; height: parent.height; color: Theme.accent }
            Rectangle { visible: !row.current; anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.jfOpen(row.modelData)
            }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.picture
                Progress { item: row.modelData }
                HdrBadge { label: row.modelData.hdr || "" }
            }
            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: watched.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: row.current ? Theme.accent : Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: [row.modelData.sub, panel.timeLeft(row.modelData)].filter((t) => t).join(" · ")
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            WatchedButton { id: watched; item: row.modelData; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    Component {
        id: jellyTile
        Tile {
            id: tile
            required property var modelData
            current: panel.playingJellyfin === modelData.id
            picture: modelData.picture
            onClicked: panel.jfOpen(modelData)
            Progress { parent: tile.thumb; item: tile.modelData }
            HdrBadge { id: jellyHdr; parent: tile.thumb; label: tile.modelData.hdr || "" }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                parent: tile.thumb
                visible: tile.current
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 6
                anchors.leftMargin: jellyHdr.visible ? jellyHdr.width + 10 : 6
                text: "PLAYING"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                anchors.left: parent.left
                anchors.right: tileWatched.left
                anchors.rightMargin: 2
                spacing: 1
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.current ? Theme.accent : Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    width: parent.width
                    elide: Text.ElideRight
                    text: [tile.modelData.sub, panel.timeLeft(tile.modelData)].filter((t) => t).join(" · ")
                    color: Theme.muted()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            WatchedButton { id: tileWatched; item: tile.modelData; anchors.right: parent.right; anchors.rightMargin: -6; y: -6 }
        }
    }

    function viewers(n) { return Number(n || 0).toLocaleString(Qt.locale("en_US"), "f", 0) }
    // A YouTube video's views as YouTube writes them ("12K views"); none
    // known (0) says nothing. Then when it came out.
    function shortViews(n) {
        n = Number(n || 0)
        if (n <= 0) return ""
        const cut = (v) => (v < 10 ? Math.floor(v * 10) / 10 : Math.floor(v)).toString()
        const num = n >= 1e9 ? cut(n / 1e9) + "B" : n >= 1e6 ? cut(n / 1e6) + "M" : n >= 1e3 ? cut(n / 1e3) + "K" : String(n)
        return num + (n === 1 ? " view" : " views")
    }
    function seenAndWhen(v) {
        return [shortViews(v.views), ago(v.published, v.rough)].filter((t) => t).join(" · ")
    }

    // Twitch's categories: box art, name, viewers; a click shows its streams.
    Component {
        id: categoryTile
        Item {
            id: tile
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            Rectangle { anchors.fill: parent; anchors.margins: 3; color: catMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent" }
            Thumb {
                id: art
                x: 6; y: 6
                width: parent.width - 12
                height: Math.round(width * 4 / 3)
                source: tile.modelData.picture
            }
            Column {
                x: 6
                anchors.top: art.bottom
                anchors.topMargin: 5
                width: parent.width - 12
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: tile.modelData.title
                    color: Theme.text(); font.family: Theme.body; font.pixelSize: 12; font.weight: Font.DemiBold }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: panel.viewers(tile.modelData.viewers) + " viewers"
                    color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11 }
            }
            MouseArea { id: catMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: panel.go({ tab: "twitch", view: "category", text: "", channel: null, arg: { name: tile.modelData.name, title: tile.modelData.title } }) }
        }
    }
    Component {
        id: categoryRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            Rectangle { anchors.fill: parent; color: catRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent" }
            Rectangle { anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            Thumb { id: art; x: 14; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 64; source: row.modelData.picture }
            Column {
                anchors.left: art.right; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.title
                    color: Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    text: panel.viewers(row.modelData.viewers) + " viewers"
                    color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11 }
            }
            MouseArea { id: catRowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: panel.go({ tab: "twitch", view: "category", text: "", channel: null, arg: { name: row.modelData.name, title: row.modelData.title } }) }
        }
    }

    // A Twitch channel's past broadcasts and clips.
    Component {
        id: recordingRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            readonly property bool current: panel.playingTwitch === modelData.id
            Rectangle { anchors.fill: parent; color: row.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (recMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent") }
            Rectangle { anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.picture
                RecordingBadges { item: row.modelData }
            }
            Column {
                anchors.left: thumb.right; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                    text: row.modelData.title
                    color: row.current ? Theme.accent : Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold; lineHeight: 1.1 }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: [panel.viewers(row.modelData.views) + " views", row.modelData.game, panel.ago(row.modelData.published)].filter((t) => t).join(" · ")
                    color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11 }
            }
            MouseArea { id: recMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.playRecording(row.modelData) }
        }
    }
    Component {
        id: recordingTile
        Tile {
            id: tile
            required property var modelData
            current: panel.playingTwitch === modelData.id
            picture: modelData.picture
            onClicked: panel.playRecording(modelData)
            RecordingBadges { parent: tile.thumb; item: tile.modelData }
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                    text: tile.modelData.title
                    color: tile.current ? Theme.accent : Theme.text(); font.family: Theme.body; font.pixelSize: 12; font.weight: Font.DemiBold; lineHeight: 1.05 }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: [panel.viewers(tile.modelData.views) + " views", panel.ago(tile.modelData.published)].filter((t) => t).join(" · ")
                    color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11 }
            }
        }
    }
    component RecordingBadges: Item {
        property var item
        anchors.fill: parent
        Rectangle {
            x: 4; y: 4
            width: kindText.implicitWidth + 8
            height: kindText.implicitHeight + 2
            color: item && item.kind === "clip" ? Theme.purple : Qt.rgba(0, 0, 0, 0.75)
            Text { id: kindText; anchors.centerIn: parent; text: item && item.kind === "clip" ? "CLIP" : "PAST BROADCAST"; color: "#ffffff"; font.pixelSize: 9; font.weight: Font.Bold; font.family: Theme.body }
        }
        Rectangle {
            visible: !!item && item.length > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4
            width: lenText.implicitWidth + 8
            height: lenText.implicitHeight + 2
            color: Qt.rgba(0, 0, 0, 0.75)
            Text { id: lenText; anchors.centerIn: parent; text: item ? panel.clock(item.length) : ""; color: Theme.text(); font.family: Theme.body; font.pixelSize: 10; font.weight: Font.DemiBold }
        }
    }

    // The playlists: first video's picture, the count, the bookmark list marked.
    Component {
        id: playlistTile
        Tile {
            id: tile
            required property var modelData
            picture: modelData.picture
            onClicked: panel.openPlaylist(modelData)
            PlaylistCount { parent: tile.thumb; item: tile.modelData }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.left: parent.left
                anchors.right: tileMark.left
                elide: Text.ElideRight
                text: tile.modelData.name
                color: Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
            IconButton {
                id: tileMark
                anchors.right: parent.right
                anchors.rightMargin: -6
                y: -7
                width: 28; height: 30
                icon: "bookmark"; iconSize: 14; filled: tile.modelData.quick
                color: tile.modelData.quick ? Theme.accent : Theme.dim()
                tip: tile.modelData.quick ? "The bookmark list" : "Make this the bookmark list"
                onClicked: Library.makeQuick(tile.modelData.id)
            }
        }
    }
    Component {
        id: playlistRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            Rectangle { anchors.fill: parent; color: plMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent" }
            Rectangle { anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            MouseArea { id: plMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.openPlaylist(row.modelData) }
            Thumb { id: thumb; x: 14; anchors.verticalCenter: parent.verticalCenter; source: row.modelData.picture; PlaylistCount { item: row.modelData } }
            Column {
                anchors.left: thumb.right; anchors.leftMargin: 12; anchors.right: rowMark.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.name
                    color: Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.count + (row.modelData.count === 1 ? " video" : " videos") + (row.modelData.played > 0 ? " · played " + panel.ago(new Date(row.modelData.played * 1000).toISOString()) : "")
                    color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11 }
            }
            IconButton {
                id: rowMark
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34
                icon: "bookmark"; iconSize: 15; filled: row.modelData.quick
                color: row.modelData.quick ? Theme.accent : Theme.dim()
                tip: row.modelData.quick ? "The bookmark list" : "Make this the bookmark list"
                onClicked: Library.makeQuick(row.modelData.id)
            }
        }
    }
    component PlaylistCount: Rectangle {
        property var item
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(34, parent.width * 0.3)
        color: Qt.rgba(0, 0, 0, 0.65)
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: item ? String(item.count) : ""; color: Theme.text(); font.family: Theme.display; font.pixelSize: 16; font.weight: Font.Bold }
            HudIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "list"; size: 13; lineWidth: 2.2; color: Theme.text() }
        }
    }

    // How far a YouTube video is watched (this computer's history): the
    // gold line, and a check mark once watched.
    component YtProgress: Item {
        property var mark
        anchors.fill: parent
        Rectangle {
            visible: !!mark && mark.p > 0.01 && !mark.done
            anchors.bottom: parent.bottom
            width: parent.width
            height: 3
            color: "#3a3842"
            Rectangle { width: parent.width * (mark ? mark.p : 0); height: 3; color: Theme.accent }
        }
        Rectangle {
            visible: !!mark && mark.done
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            width: 18
            height: 18
            color: Theme.accent
            HudIcon { anchors.centerIn: parent; name: "check"; size: 12; lineWidth: 2.6; color: "#0c0c0f" }
        }
    }

    // HDR on a video's picture (MN, 2026-11-19): bottom left, gold as the
    // player's badge. YouTube's from Streams.hdrOf (looked at once per
    // video), Jellyfin's from the item ("HDR", "HDR10+", "DV").
    component HdrBadge: Rectangle {
        property string label
        visible: label !== ""
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 4
        width: hdrLabel.implicitWidth + 8
        height: hdrLabel.implicitHeight + 2
        color: Theme.accent
        Text {
            id: hdrLabel
            anchors.centerIn: parent
            text: parent.label
            color: "#0c0c0f"
            font.family: Theme.display
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
    }
    function ytHdr(video) {
        return video && !video.live && Streams.hdrRevision >= 0 && Streams.hdrOf(video.id) === "hdr" ? "HDR" : ""
    }

    // The bookmark: the video into the bookmark list ("Watch later") or out.
    component BookmarkButton: IconButton {
        property var video
        property var mark
        readonly property bool on: !!mark && mark.quick
        icon: "bookmark"
        iconSize: 15
        filled: on
        color: on ? Theme.accent : Theme.dim()
        tip: on ? "Remove from the bookmark list" : "Bookmark (into “" + panel.quickName + "”)"
        onClicked: Library.toggleQuick(JSON.stringify(video))
    }
    readonly property string quickName: (playlists.find((p) => p.quick) || { name: "Watch later" }).name

    // How far an item is watched: a thin gold line along the picture's foot;
    // a watched one gets a check mark.
    component Progress: Item {
        property var item
        anchors.fill: parent
        Rectangle {
            visible: !!item && item.percent > 0 && !item.played
            anchors.bottom: parent.bottom
            width: parent.width
            height: 3
            color: "#3a3842"
            Rectangle { width: parent.width * (item ? item.percent : 0) / 100; height: 3; color: Theme.accent }
        }
        Rectangle {
            visible: !!item && (item.played || item.unplayed > 0)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            width: Math.max(18, unplayedText.implicitWidth + 8)
            height: 18
            color: item && item.played ? Theme.accent : Qt.rgba(0, 0, 0, 0.75)
            HudIcon { visible: !!(item && item.played); anchors.centerIn: parent; name: "check"; size: 12; lineWidth: 2.6; color: "#0c0c0f" }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: unplayedText
                visible: !!item && !item.played && item.unplayed > 0
                anchors.centerIn: parent
                text: item ? String(item.unplayed) : ""
                color: Theme.text()
                font.family: Theme.body
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    // Marks an item watched or not (films and episodes).
    component WatchedButton: IconButton {
        property var item
        visible: !!item && item.playable
        width: visible ? 30 : 0
        height: 30
        icon: "check"
        iconSize: 15
        color: item && item.played ? Theme.accent : Theme.dim()
        tip: item && item.played ? "Mark as not watched" : "Mark as watched"
        onClicked: Jellyfin.setPlayed(item.id, !item.played)
    }

    component Thumb: Rectangle {
        property alias source: img.source
        property bool dimmed: false
        width: 112
        height: 63
        color: "#1f1e25"
        clip: true
        Image {
            id: img
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            opacity: parent.dimmed ? 0.5 : 1
            sourceSize.width: 320
        }
    }

    // A YouTube channel's picture (square, as Twitch's), its first letter
    // until the picture is there.
    component ChannelPicture: Rectangle {
        id: channelPicture
        property var channel
        property int size: 40
        readonly property string source: (channel && panel.channelPictures[channel.id]) || ""
        width: size
        height: size
        color: "#1f1e25"
        clip: true
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            anchors.centerIn: parent
            visible: pictureImage.status !== Image.Ready
            text: ((channelPicture.channel && channelPicture.channel.name) || "?").charAt(0).toUpperCase()
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: Math.round(channelPicture.size * 0.42)
            font.weight: Font.DemiBold
        }
        Image {
            id: pictureImage
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            source: channelPicture.source
            sourceSize.width: 88
            sourceSize.height: 88
        }
    }

    component SiteTab: Item {
        property string name
        property string label
        width: siteText.implicitWidth
        height: 30
        readonly property bool current: Streams.tab === name
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: siteText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: !parent.enabled ? Theme.dim() : parent.current ? Theme.accent : (siteMouse.containsMouse ? Theme.text() : Theme.muted())
            font.family: Theme.display
            font.pixelSize: 14
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: !parent.enabled
            anchors.left: siteText.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "NEXT"
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        Rectangle {
            visible: parent.current
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Theme.accent
        }
        MouseArea {
            id: siteMouse
            anchors.fill: parent
            enabled: parent.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (Streams.tab === parent.name) return
                const view = parent.name === "twitch" ? Streams.twitchView
                    : parent.name === "jellyfin" ? (Jellyfin.view === "folder" || Jellyfin.view === "search" ? "libraries" : Jellyfin.view)
                    : (Streams.youtubeView === "channel" ? "channels" : Streams.youtubeView)
                panel.go({ tab: parent.name, view: view, text: "", channel: null, path: [] })
            }
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }

    component ListTab: Item {
        property string name
        property string label
        property bool purple: false
        property bool searchIcon: false
        property bool twitch: false
        /// "twitch", "youtube" or "jellyfin" (twitch: true says "twitch").
        property string site: twitch ? "twitch" : "youtube"
        /// Views that belong to this tab too (an open playlist, a channel).
        property var also: []
        /// A red count beside the label (channels gone live).
        property int count: 0
        readonly property string viewNow: site === "jellyfin" ? (Jellyfin.view === "folder" ? "libraries" : Jellyfin.view)
            : site === "twitch" ? Streams.twitchView : Streams.youtubeView
        readonly property bool current: viewNow === name || also.indexOf(viewNow) >= 0
        width: searchIcon ? 20 : tabRow.implicitWidth
        height: parent.height
        Row {
            id: tabRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle { visible: purple; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; color: Theme.purple }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                visible: !searchIcon
                text: label.toUpperCase()
                color: current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Rectangle {
                visible: count > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(16, countText.implicitWidth + 8)
                height: 16
                color: Theme.red
                Text { id: countText; anchors.centerIn: parent; text: String(count); color: "#ffffff"; font.family: Theme.body; font.pixelSize: 10; font.weight: Font.Bold }
            }
            HudIcon {
                visible: searchIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 15
                lineWidth: 2
                color: current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
            }
        }
        Rectangle {
            visible: current
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Theme.accent
        }
        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.go({ tab: site, view: name, text: "", channel: null, path: [] })
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: searchIcon ? "Search" : label
    }

    // A row of list tabs that scrolls sideways when the panel is narrow.
    component TabStrip: Flickable {
        default property alias tabs: strip.data
        width: parent.width
        height: parent.height
        contentWidth: strip.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
            id: strip
            height: parent.height
            spacing: 14
        }
    }

    // A filter of the YouTube search: a chip opening its choices.
    component FilterChip: Chip {
        id: fc
        property string key
        property string label
        property var options: []
        property string current
        text: label + ": " + ((options.find((o) => o.id === current) || {}).name || current)
        on: current !== "any" && current !== "relevance"
        onClicked: panel.openMenu(fc, "filter", { options: options, choose: (id) => {
            Streams.changeSearchFilter(key, id)
            if (search.text.trim().length > 0) Streams.loadYoutube("search", search.text)
        } })
    }

    component Field: Rectangle {
        property alias text: input.text
        property string placeholder
        signal accepted
        function focusInput() { input.forceActiveFocus() }
        height: 32
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
            font.family: Theme.body
            font.pixelSize: 13
            maximumLength: 80
            clip: true
            onAccepted: parent.accepted()
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
}
