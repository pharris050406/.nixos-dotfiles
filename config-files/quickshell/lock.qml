import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "Lib.js" as Lib

// The lock screen: tonight's sky, the time, and a row of segments to type into.
// Started by the `lockscreen` script as its own process,
//     quickshell -p ~/.config/quickshell/lock.qml
// so nothing in the bar can affect it, and it costs nothing until you lock.
//
// How it stays secure:
//  * The compositor does the locking (Wayland ext-session-lock), not this
//    program. If this process crashed, sway would keep the session locked
//    (solid colour) instead of showing it; the script then falls back to swaylock.
//  * The one way to unlock is PAM saying Success for your password
//    (PAM service "quickshell-lock", set up in modules/nixos/session.nix).
//  * The password is never drawn, logged or passed as a process argument. It
//    lives in memory from typing until it's handed to PAM, then it's cleared.
//    The input shows a blip per key at a random spot, so not even its length shows.
ShellRoot {
    id: root

    // Same place as the bar's shell.qml, for the sky.
    readonly property real latitude: 34.05
    readonly property real longitude: -118.25

    Theme { id: pal }
    readonly property color label: Lib.mix(pal.foreground, pal.muted, 0.5)
    readonly property color edge: Lib.mix(pal.muted, pal.barColor, 0.35)

    // ---------------- state for the lockscreen script ----------------
    // "locked" once the compositor confirms every screen is covered (the
    // script waits for that before letting the machine sleep), "unlocked"
    // just before letting go.
    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-lock.state"
        printErrors: false
    }

    // ---------------- authentication ----------------
    property string buffer: ""          // what's been typed
    property string pending: ""         // password waiting for PAM to ask for it
    property string phase: "idle"       // idle | checking | denied | error | open
    property string note: ""            // PAM's own message, when it has one worth showing

    function clear() { buffer = ""; }

    function submit() {
        if (phase === "checking" || phase === "open") return;
        if (pam.active && pam.responseRequired) {        // PAM asked a follow-up question
            var r = buffer;
            buffer = "";
            phase = "checking";
            pam.respond(r);
            return;
        }
        if (buffer === "") return;
        pending = buffer;
        buffer = "";
        note = "";
        phase = "checking";
        if (!pam.start()) {
            pending = "";
            phase = "error";
            note = "couldn't start authentication";
        }
    }

    PamContext {
        id: pam
        config: "quickshell-lock"

        onPamMessage: {
            if (responseRequired) {
                if (root.pending !== "") {                // the password prompt: answer it
                    var p = root.pending;
                    root.pending = "";
                    respond(p);
                } else {                                  // anything further: show it, wait for input
                    root.note = message;
                    root.phase = "idle";
                }
            } else if (messageIsError) {
                root.note = message;
            }
        }

        onCompleted: result => {
            root.pending = "";
            if (result === PamResult.Success) {
                root.phase = "open";
                stateFile.setText("unlocked\n");
                lock.locked = false;
                quit.start();
            } else if (result === PamResult.Failed) {
                root.phase = "denied";
            } else {
                root.phase = "error";
                if (result === PamResult.MaxTries) root.note = "too many attempts";
                else if (root.note === "") root.note = "authentication error";
            }
        }
    }
    Timer { id: quit; interval: 300; onTriggered: Qt.quit() }

    // ---------------- key blips (shared by every screen) ----------------
    readonly property int blips: 16
    property int blip: -1
    property bool blipBad: false
    function flash(bad) {
        blip = Math.floor(Math.random() * blips);
        blipBad = bad;
        blipOff.restart();
    }
    Timer { id: blipOff; interval: 260; onTriggered: root.blip = -1 }

    // ---------------- clock: wakes once a minute ----------------
    property date now: new Date()
    Timer {
        running: true
        interval: 60000 - Date.now() % 60000 + 50
        repeat: true
        onTriggered: {
            root.now = new Date();
            interval = 60000 - Date.now() % 60000 + 50;
        }
    }

    // ---------------- the lock ----------------
    WlSessionLock {
        id: lock
        locked: true
        onSecureChanged: if (secure) stateFile.setText("locked\n")

        WlSessionLockSurface {
            id: surface
            color: pal.background

            // The sky loads once the screen is already locked, so locking is
            // never held up by it. No meteors, and a redraw every 2 minutes.
            Loader {
                anchors.fill: parent
                active: lock.secure
                asynchronous: true
                sourceComponent: SkyView {
                    theme: pal
                    latitude: root.latitude
                    longitude: root.longitude
                    meteors: false
                    refreshMs: 120000
					interactive: false
                }
            }
            Rectangle { anchors.fill: parent; color: pal.background; opacity: 0.45 }

            // The sky is just a picture here: swallow every click, scroll and hover.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                onPressed: keys.forceActiveFocus()
                onWheel: w => w.accepted = true
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: e => {
                    e.accepted = true;
                    if (root.phase === "checking" || root.phase === "open") return;
                    var ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.submit();
                    else if (e.key === Qt.Key_Escape || (ctrl && e.key === Qt.Key_U)) { root.clear(); root.flash(true); }
                    else if (e.key === Qt.Key_Backspace) { root.buffer = root.buffer.slice(0, -1); root.flash(true); }
                    else if (!ctrl && e.text !== "" && e.text.charCodeAt(0) >= 32) {
                        root.buffer += e.text;
                        if (root.phase === "denied" || root.phase === "error") root.phase = "idle";
                        root.flash(false);
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(root.now, "HH:mm")
                    color: pal.foreground
                    font { family: pal.fontFamily; pixelSize: pal.fontSize * 7; weight: Font.Light }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(root.now, "dddd · d MMMM").toUpperCase()
                    color: root.label
                    font { family: pal.fontFamily; pixelSize: pal.fontSize - 1; letterSpacing: 3 }
                }

                Item { width: 1; height: 28 }

                // Input: a row of segments. Each key lights one at random (never
                // showing the length); the whole row turns yellow while checking,
                // red when the password is wrong, green as it opens.
                Row {
                    id: segments
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    readonly property color rest: root.phase === "checking" ? pal.accent4
                        : root.phase === "denied" || root.phase === "error" ? pal.accent6
                        : root.phase === "open" ? pal.accent3
                        : root.buffer !== "" ? Lib.mix(pal.muted, pal.foreground, 0.25)
                        : root.edge
                    Repeater {
                        model: root.blips
                        Rectangle {
                            required property int index
                            width: 14
                            height: 3
                            color: index === root.blip ? (root.blipBad ? pal.accent6 : pal.accent3) : segments.rest
                        }
                    }
                }

                Text {
                    visible: root.note !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 300
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: root.note
                    color: root.phase === "error" ? pal.accent6 : root.label
                    font { family: pal.fontFamily; pixelSize: pal.fontSize - 2 }
                }
            }
        }
    }
}
