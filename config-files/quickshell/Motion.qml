pragma Singleton
import QtQuick
import Quickshell

// One clock for every ambient animation (orbiting moon, radio pulse, comms
// scope). Everything moves on the same 20 fps tick, so the bar redraws at most
// 20 times a second instead of each widget running its own 60 fps animation.
// shell.qml switches it off on battery unless you say otherwise.
Singleton {
    id: motion

    property bool live: true
    property real t: 0                         // seconds, wraps every ~2.8 h

    Timer {
        interval: 50
        repeat: true
        running: motion.live
        onTriggered: motion.t = (Date.now() % 1e7) / 1000
    }
}
