import QtQuick
import Quickshell
import "Lib.js" as Lib

// Now playing, as an incoming transmission.
//  - A beacon: steady carrier while playing (with a radio pulse every 2.4 s),
//    hollow while paused.
//  - Track change is Doppler-shifted. The old title recedes and redshifts
//    away; the new one approaches blueshifted and settles to rest.
//  - Progress is drawn as a spacecraft on the bar's bottom edge (Trajectory).
//   left: play/pause   right: next   middle: previous   wheel: ±5 s
Item {
    id: tx

    property Theme theme
    property real maxWidth: 380

    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)
    readonly property int beaconW: 12
    readonly property int gap: 8

    visible: Media.active
    implicitHeight: theme.fontSize + 8
    implicitWidth: Math.max(0, Math.min(maxWidth, beaconW + gap + metrics.advanceWidth + 2))
    Behavior on implicitWidth { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    TextMetrics {
        id: metrics
        font { family: tx.theme.fontFamily; pixelSize: tx.theme.fontSize }
        text: tx.shown
    }

    // ---------------- beacon ----------------
    readonly property real pulse: Media.playing && Motion.live ? (Motion.t % 2.4) / 2.4 : 1
    Item {
        id: beacon
        width: tx.beaconW
        height: tx.height
        Rectangle {
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            scale: 1 + 1.6 * tx.pulse
            opacity: (1 - tx.pulse) * 0.7
            color: "transparent"
            border.width: 1
            border.color: tx.theme.accent2
        }
        Rectangle {
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            color: Media.playing ? tx.theme.accent2 : "transparent"
            border.width: Media.playing ? 0 : 1.5
            border.color: tx.theme.accent2
        }
    }

    // ---------------- Doppler swap ----------------
    // shift: -1 fully redshifted ... 0 rest ... +1 fully blueshifted
    property real shift: 0
    property string shown: ""
    Component.onCompleted: shown = Media.track
    Connections {
        target: Media
        function onTrackChanged() {
            if (!tx.visible || tx.shown === "" || Media.track === "" || !Motion.live) tx.shown = Media.track;
            else doppler.restart();
        }
    }
    SequentialAnimation {
        id: doppler
        ParallelAnimation {     // recede
            NumberAnimation { target: tx; property: "shift"; to: -1; duration: 200; easing.type: Easing.InQuad }
            NumberAnimation { target: title; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InQuad }
            NumberAnimation { target: title; property: "scale"; to: 0.9; duration: 200; easing.type: Easing.InQuad }
            NumberAnimation { target: title; property: "x"; to: -8; duration: 200; easing.type: Easing.InQuad }
        }
        ScriptAction { script: { tx.shown = Media.track; tx.shift = 1; title.scale = 1.08; title.x = 10; } }
        ParallelAnimation {     // approach and come to rest
            NumberAnimation { target: tx; property: "shift"; to: 0; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: title; property: "opacity"; to: 1; duration: 260 }
            NumberAnimation { target: title; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: title; property: "x"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: box
        x: tx.beaconW + tx.gap
        width: Math.max(0, tx.width - x)
        height: tx.height
        clip: true

        Text {
            id: title
            width: parent.width
            height: parent.height
            transformOrigin: Item.Left
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: tx.shown
            readonly property color rest: Media.playing ? tx.theme.foreground : tx.label
            color: tx.shift > 0 ? Lib.mix(rest, tx.theme.accent2, tx.shift)
                 : tx.shift < 0 ? Lib.mix(rest, tx.theme.accent6, -tx.shift)
                 : rest
            font { family: tx.theme.fontFamily; pixelSize: tx.theme.fontSize }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => {
            if (m.button === Qt.LeftButton) Media.toggle();
            else if (m.button === Qt.RightButton) Media.next();
            else Media.previous();
        }
        onWheel: w => Media.nudge(w.angleDelta.y > 0 ? 5 : -5)
    }

    // ---------------- card ----------------
    TextMetrics {
        id: fullMetrics
        font { family: tx.theme.fontFamily; pixelSize: tx.theme.fontSize }
        text: Media.track
    }
    readonly property real firstNote: Lib.lightDistance(Media.position)
    readonly property string firstPast: Lib.pastOrbit(firstNote)
    readonly property real wholeTrack: Lib.lightDistance(Media.length)

    Card {
        theme: tx.theme
        target: tx
        accent: tx.theme.accent2
        heading: "transmission"
        subheading: Media.sourceName ? "via " + Media.sourceName : ""
        want: mouse.containsMouse && Media.active

        Text {
            width: Math.min(440, Math.ceil(fullMetrics.advanceWidth) + 2)
            wrapMode: Text.Wrap
            text: Media.track
            color: tx.theme.foreground
            font { family: tx.theme.fontFamily; pixelSize: tx.theme.fontSize }
        }
        Readout {
            theme: tx.theme; k: Media.playing ? "receiving" : "paused"
            v: Lib.clock(Media.position) + (Media.length > 0 ? " / " + Lib.clock(Media.length) : "")
        }
        Readout {
            theme: tx.theme; k: "first note"
            v: Lib.distance(tx.firstNote) + " away"
               + (tx.firstPast ? ", past " + tx.firstPast : Media.position > 0 ? ", inside mercury's orbit" : "")
        }
        Readout {
            visible: Media.length > 0
            theme: tx.theme; k: "whole track"; dim: true
            v: Lib.distance(tx.wholeTrack) + " of light"
        }
        Text {
            topPadding: 4
            text: "click pause · right next · middle prev · wheel ±5s · bottom edge seeks"
            color: tx.theme.muted
            font { family: tx.theme.fontFamily; pixelSize: tx.theme.fontSize - 3 }
        }
    }
}
