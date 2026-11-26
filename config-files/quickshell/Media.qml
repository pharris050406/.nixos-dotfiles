pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Now-playing state, straight from MPRIS over D-Bus (no helper processes).
//
// It follows one *pinned* player and never switches on its own: opening
// YouTube while mpd is pinned changes nothing here. The pin is the player's
// playerctl-style name in ~/.cache/quickshell/selected-player, written by
// `media-ctl.sh cycle` (your media key). Same rules as media-ctl.sh:
//   the pinned player if it's running; else the same app under a new
//   instance number (firefox.instance_1_3 -> firefox.instance_2_7);
//   else the first player by name.
Singleton {
    id: media

    // ---------------- which player ----------------
    property string playerName: ""            // the pin, e.g. "mpd"

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/selected-player"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: media.playerName = text().trim()
        onLoadFailed: media.playerName = ""
    }

    // org.mpris.MediaPlayer2.firefox.instance_1_3 -> firefox.instance_1_3
    function nameOf(p) { return (p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, ""); }

    readonly property var players: Mpris.players.values
        .filter(p => nameOf(p) !== "playerctld")        // playerctld mirrors whichever was last active
        .sort((a, b) => nameOf(a) < nameOf(b) ? -1 : nameOf(a) > nameOf(b) ? 1 : 0)

    readonly property MprisPlayer player: {
        var ps = players;
        if (ps.length === 0) return null;
        var pin = playerName;
        if (pin !== "") {
            var exact = ps.find(p => nameOf(p) === pin);
            if (exact) return exact;
            var app = pin.split(".")[0];
            var same = ps.find(p => nameOf(p).indexOf(app) === 0);
            if (same) return same;
        }
        return ps[0];
    }

    // ---------------- state (same API the widgets already use) ----------------
    readonly property string status: !player ? ""
        : player.playbackState === MprisPlaybackState.Playing ? "Playing"
        : player.playbackState === MprisPlaybackState.Paused ? "Paused" : "Stopped"
    readonly property bool playing: status === "Playing"
    readonly property bool active: status === "Playing" || status === "Paused"

    readonly property string track: !active ? ""
        : player.trackTitle + (player.trackArtist ? " - " + player.trackArtist : "")

    // Length. Firefox drops mpris:length from its metadata after a seek and
    // only sends it again on the next state change, so the last length a
    // track reported is remembered and used while that same track plays.
    readonly property real rawLength: player && player.lengthSupported ? player.length : 0
    readonly property string trackKey: active ? nameOf(player) + "|" + track : ""
    property real _knownLength: 0
    property string _knownFor: ""
    function _remember() { if (rawLength > 0) { _knownLength = rawLength; _knownFor = trackKey; } }
    onRawLengthChanged: _remember()
    onTrackKeyChanged: _remember()
    readonly property real length: !active ? 0
        : rawLength > 0 ? rawLength
        : trackKey === _knownFor ? _knownLength : 0

    readonly property string sourceId: active ? nameOf(player) : ""      // e.g. "firefox.instance_1_3"
    readonly property string sourceName: sourceId.split(".")[0]          // e.g. "firefox"

    // Position. Reading player.position always gives the current value, but it
    // only announces jumps (seeks, track changes), not the steady ticking. So:
    //   basePos     last value read; widgets bind to it to know "something moved"
    //   position    re-read once a second while playing, for text
    //   estimate()  the playhead right now, for anything smoother
    property real basePos: 0
    property real position: 0
    property real _seekTarget: -1             // until the player confirms a seek, show where we sent it
    property real _holdUntil: 0

    function estimate() {
        if (!active) return 0;
        if (Date.now() < _holdUntil) return _seekTarget;
        var p = player.position;
        return length > 0 ? Math.max(0, Math.min(p, length)) : Math.max(0, p);
    }
    function _sync() {
        var p = estimate();
        basePos = p;
        position = p;
    }

    Timer {
        interval: 1000; repeat: true; running: media.playing
        onTriggered: media._sync()
    }
    Connections {                             // seeks and track changes, from anywhere
        target: media.player
        function onPositionChanged() {
            if (Date.now() < media._holdUntil && Math.abs(media.player.position - media._seekTarget) < 1.5)
                media._endHold();             // the player has caught up with our seek
            media._sync();
        }
    }
    onStatusChanged: _sync()
    onPlayerChanged: { _endHold(); _sync(); }
    onTrackChanged: _sync()

    function _endHold() { _holdUntil = 0; holdEnd.stop(); }
    Timer { id: holdEnd; interval: 3000; onTriggered: { media._endHold(); media._sync(); } }

    // ---------------- controls ----------------
    function toggle() { if (player && player.canTogglePlaying) player.togglePlaying(); }
    function next() { if (player && player.canGoNext) player.next(); }
    function previous() { if (player && player.canGoPrevious) player.previous(); }

    // Seeking goes to an absolute position (MPRIS SetPosition). A relative Seek
    // looks simpler, but Firefox turns it into the page's own skip-forward/back,
    // and YouTube skips by its own step instead of the amount asked for.
    // Players that can't report a position get the relative Seek anyway.
    function seek(sec) {
        if (!active || !player.canSeek) return;
        var target = Math.max(0, length > 0 ? Math.min(sec, length - 1) : sec);
        if (player.positionSupported) player.position = target;
        else player.seek(target - estimate());
        _seekTarget = target;                 // show it now; the player catches up
        _holdUntil = Date.now() + 3000;
        holdEnd.restart();
        _sync();
    }
    function nudge(delta) { seek(estimate() + delta) }
}
