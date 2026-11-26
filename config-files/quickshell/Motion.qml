pragma Singleton
import QtQuick
import Quickshell

// One clock for every ambient animation (orbiting moon, radio pulse, comms
// scope), so the bar redraws at most once per tick instead of each widget
// running its own 60 fps animation.
// It ticks at 20 fps only while something fast is on screen (music playing:
// the radio pulse; network traffic: the comms scope) and at 5 fps otherwise,
// when only the moon is moving. shell.qml turns it off on battery if
// motionOnBattery is false.
Singleton {
    id: motion

    property bool live: true
    property int fastMs: 50
    property int idleMs: 200
    readonly property bool fast: Media.playing || Net.activity > 0.02
    property real t: 0                         // seconds, wraps every ~2.8 h

    Timer {
        interval: motion.fast ? motion.fastMs : motion.idleMs
        repeat: true
        running: motion.live
        onTriggered: motion.t = (Date.now() % 1e7) / 1000
    }
}
