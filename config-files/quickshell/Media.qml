pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Now-playing state. Same media-source.sh and META|/POS| protocol as before,
// same pinned player (~/.cache/quickshell/selected-player) for controls.
Singleton {
    id: media

    property string status: ""
    property string track: ""
    property real length: 0              // seconds
    property real basePos: 0             // last position the script reported
    property real baseStamp: 0           // Date.now() when it arrived
    property real position: 0            // ticks once a second, for text
    property string playerName: ""
    property string sourceName: ""       // e.g. "firefox"
    property string sourceId: ""         // e.g. "firefox.instance_1_3" (what -p wants)

    readonly property bool playing: status === "Playing"
    readonly property bool active: status === "Playing" || status === "Paused"

    // Playhead estimate at this instant (between the script's 1s reports).
    function estimate() {
        var p = playing ? basePos + (Date.now() - baseStamp) / 1000 : basePos;
        return length > 0 ? Math.max(0, Math.min(p, length)) : Math.max(0, p);
    }
    function _setPos(p) {
        basePos = p;
        baseStamp = Date.now();
        position = p;
    }

    Process {
        command: ["sh", "-c", "exec \"$HOME/.config/quickshell/scripts/media-source.sh\""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                var val = data.trim();
                if (val.indexOf("META|") === 0) {
                    var parts = val.substring(5).split("|");
                    if (parts.length < 3) return;
                    var micro = parseFloat(parts[1]);
                    media.status = parts[0];
                    if (parts.slice(2).join("|") !== media.track) media._holdUntil = 0;
                    if (media.active) {
                        media.length = isNaN(micro) ? 0 : micro / 1000000;
                        media.track = parts.slice(2).join("|");
                    } else {
                        media.length = 0;
                        media.track = "";
                        media._setPos(0);
                    }
                } else if (val.indexOf("POS|") === 0) {
                    var p = parseFloat(val.substring(4));
                    if (isNaN(p)) return;
                    // Right after a seek, a report can predate it and would yank the
                    // playhead back. Until one agrees with the seek (or 3 s pass),
                    // ignore reports that disagree with where we sent it.
                    if (Date.now() < media._holdUntil) {
                        if (Math.abs(p - media.estimate()) > 1.5) return;
                        media._holdUntil = 0;
                    }
                    media._setPos(p);
                }
            }
        }
    }

    // Freeze/unfreeze the playhead where it actually is, not at the last tick.
    property bool _wasPlaying: false
    onPlayingChanged: {
        var p = _wasPlaying ? basePos + (Date.now() - baseStamp) / 1000 : basePos;
        _wasPlaying = playing;
        _setPos(length > 0 ? Math.min(p, length) : p);
    }
    Timer {
        interval: 1000; repeat: true; running: media.playing
        onTriggered: media.position = media.estimate()
    }

    // ---- which player is actually feeding us (shown in the hover card) ----
    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/selected-player"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { media.playerName = text().trim(); media.refreshSource(); }
        onLoadFailed: { media.playerName = ""; media.refreshSource(); }
    }

    property bool _again: false
    Process {
        id: sourceProc
        command: ["sh", "-c", "playerctl -a metadata --format '{{playerInstance}}|{{title}}' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var found = "", match = "";
                for (const line of this.text.split("\n")) {
                    var i = line.indexOf("|");
                    if (i < 0) continue;
                    var name = line.slice(0, i), title = line.slice(i + 1);
                    if (name === "playerctld") continue;
                    if (name === media.playerName) found = name;
                    if (!match && title && media.track.indexOf(title) >= 0) match = name;
                }
                media.sourceId = media.active ? (found || match) : "";
                media.sourceName = media.sourceId.split(".")[0];
            }
        }
        onExited: if (media._again) { media._again = false; running = true; }
    }
    function refreshSource() {
        if (sourceProc.running) _again = true;
        else sourceProc.running = true;
    }
    onStatusChanged: refreshSource()
    onTrackChanged: refreshSource()

    // ---- controls: go to the pinned player, same as the keybinds ----
    Process { id: ctlProc }
    function ctl(args) {
        ctlProc.running = false;
        ctlProc.command = ["sh", "-c",
            "p=$(cat \"$HOME/.cache/quickshell/selected-player\" 2>/dev/null); " +
            "exec playerctl ${p:+-p \"$p\"} \"$@\"", "sh"].concat(args);
        ctlProc.running = true;
    }
    function toggle() { ctl(["play-pause"]) }
    function next() { ctl(["next"]) }
    function previous() { ctl(["previous"]) }
    // Seeking. MPRIS has two ways in: SetPosition (absolute) and Seek
    // (relative). SetPosition carries a track id, and the spec says a player
    // must *silently ignore* it if the id doesn't match its current one, so
    // playerctl exits 0 and nothing happens. Seek has no track id, so that's
    // what we use: ask the player where it really is, seek by the difference,
    // and only fall back to SetPosition if that fails.
    // It goes to the player actually feeding the bar (sourceId), else the
    // pinned one. Clicks during a seek coalesce to the newest target.
    property real _seekTarget: -1
    property real _holdUntil: 0
    Process {
        id: seekProc
        stderr: StdioCollector { id: seekErr }
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("seek failed (" + code + "): " + seekErr.text.trim());
            if (media._seekTarget >= 0) {
                var t = media._seekTarget;
                media._seekTarget = -1;
                Qt.callLater(() => media._runSeek(t));
            }
        }
    }
    function _runSeek(target) {
        _setPos(target);                         // optimistic
        _holdUntil = Date.now() + 3000;
        seekProc.command = ["sh", "-c",
            "p=$1; t=$2; [ -n \"$p\" ] || p=$(cat \"$HOME/.cache/quickshell/selected-player\" 2>/dev/null); " +
            "cur=$(playerctl ${p:+-p \"$p\"} position 2>/dev/null); " +
            "if [ -n \"$cur\" ]; then " +
            "  d=$(awk -v t=\"$t\" -v c=\"$cur\" 'BEGIN { d = t - c; printf \"%.2f%s\", (d < 0 ? -d : d), (d < 0 ? \"-\" : \"+\") }'); " +
            "  playerctl ${p:+-p \"$p\"} position \"$d\" && exit 0; " +
            "fi; " +
            "exec playerctl ${p:+-p \"$p\"} position \"$t\"",
            "sh", sourceId, target.toFixed(2)];
        seekProc.running = true;
    }
    function seek(sec) {
        var target = Math.max(0, length > 0 ? Math.min(sec, length - 1) : sec);
        if (seekProc.running) {                  // show it now, send it when the last one lands
            _seekTarget = target;
            _setPos(target);
            _holdUntil = Date.now() + 3000;
        }
        else _runSeek(target);
    }
    function nudge(delta) { seek(estimate() + delta) }
}
