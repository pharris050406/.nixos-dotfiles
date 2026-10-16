import QtQuick
import "Lib.js" as Lib

// The bar's bottom edge is a flight path.
//  - A spacecraft flies left to right across the whole bar as the song plays,
//    leaving an exhaust trail behind and a dotted planned course ahead,
//    toward an arrival marker at the far edge. Paused, it coasts (greys out).
//  - Hover the edge to see where you'd land; click to make a course correction.
//  - The hairline turns red while anything is in caution (cpu, memory, comms,
//    power), so you catch it in peripheral vision.
// The ship steps exactly as often as it needs to move one pixel
// (song length ÷ bar width), so playback never redraws at 60 fps.
Item {
    id: path

    property Theme theme
    height: 7

    readonly property bool hasTrack: Media.active && Media.length > 0
    readonly property bool caution: Sys.cpuHot || Sys.memHot || Net.offline || Net.unreachable || Sys.batteryLow
    readonly property color shipColor: Media.playing ? theme.accent2 : theme.muted

    property int tick: 0
    readonly property real frac: {
        tick; Media.basePos; Media.status;
        return hasTrack ? Lib.clamp01(Media.estimate() / Media.length) : 0;
    }
    readonly property real shipX: Math.round(width * frac)

    Timer {
        running: Media.playing && path.hasTrack
        repeat: true
        interval: Math.max(100, Math.min(1000, Math.round(Media.length * 1000 / Math.max(1, path.width))))
        onTriggered: path.tick++
    }

    // hairline
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: path.caution ? path.theme.accent6 : Lib.mix(path.theme.muted, path.theme.background, 0.35)
        Behavior on color { ColorAnimation { duration: 600 } }
    }

    // planned course: dots from the ship to the arrival marker
    Item {
        visible: path.hasTrack
        x: path.shipX
        width: Math.max(0, path.width - path.shipX)
        height: path.height
        clip: true
        Canvas {
            id: course
            x: -parent.x
            width: path.width
            height: path.height
            property color c: path.shipColor
            onCChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = Lib.css(c, 0.55);
                for (var x = 0; x < width; x += 5) ctx.fillRect(x, height - 2, 1, 1);
            }
        }
    }

    // exhaust trail
    Rectangle {
        visible: path.hasTrack
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: path.shipX
        height: scrub.containsMouse ? 3 : 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.75; color: Qt.rgba(path.shipColor.r, path.shipColor.g, path.shipColor.b, 0.35) }
            GradientStop { position: 1.0; color: path.shipColor }
        }
    }

    // arrival marker
    Rectangle {
        visible: path.hasTrack
        x: path.width - width - 2
        anchors.bottom: parent.bottom
        width: 5; height: 5; radius: 2.5
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(path.shipColor.r, path.shipColor.g, path.shipColor.b, 0.7)
    }

    // the ship
    Canvas {
        id: ship
        visible: path.hasTrack
        width: 9; height: 6
        x: path.shipX - width + 2
        anchors.bottom: parent.bottom
        property color c: path.shipColor
        onCChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Lib.css(c, 1);
            ctx.beginPath();
            ctx.moveTo(width, height - 1.5);
            ctx.lineTo(0, 0.5);
            ctx.lineTo(2.5, height - 1.5);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fill();
        }
    }

    // ---- course correction ----
    Rectangle {
        visible: scrub.containsMouse && path.hasTrack
        x: Math.round(scrub.mouseX)
        anchors.bottom: parent.bottom
        width: 1
        height: path.height
        color: path.theme.foreground
    }
    Rectangle {
        id: eta
        visible: scrub.containsMouse && path.hasTrack
        x: Math.max(0, Math.min(path.width - width, scrub.mouseX - width / 2))
        y: -height - 3
        width: etaText.implicitWidth + 10
        height: etaText.implicitHeight + 2
        radius: 3
        color: Qt.rgba(path.theme.barColor.r, path.theme.barColor.g, path.theme.barColor.b, 0.95)
        border.width: 1
        border.color: path.theme.accent2
        Text {
            id: etaText
            anchors.centerIn: parent
            text: Lib.clock(Lib.clamp01(scrub.mouseX / Math.max(1, path.width)) * Media.length)
            color: path.theme.foreground
            font { family: path.theme.fontFamily; pixelSize: path.theme.fontSize - 3 }
        }
    }

    MouseArea {
        id: scrub
        anchors.fill: parent
        enabled: path.hasTrack
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: m => Media.seek(Lib.clamp01(m.x / width) * Media.length)
    }
}
