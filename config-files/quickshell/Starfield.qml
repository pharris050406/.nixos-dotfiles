import QtQuick
import "Lib.js" as Lib

// The bar's background: a deep field.
// Painted once per size from a fixed seed, so it's the same sky every launch.
// Star colors are blackbody colors sampled from a red-heavy temperature
// distribution (most stars are cool), brightness falls off as a power law
// (many faint, few bright), and a denser band runs through it like the
// Milky Way. Two faint nebulae take the theme's accent colors.
// Every few minutes, a meteor.
Item {
    id: field

    property Theme theme
    property bool meteors: true
    property int seed: 1977                    // Voyager's launch year

    readonly property color neb1: theme.accent7
    readonly property color neb2: theme.accent2
    onNeb1Changed: sky.requestPaint()
    onNeb2Changed: sky.requestPaint()

    Canvas {
        id: sky
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width, h = height;
            if (w <= 0 || h <= 0) return;
            var rnd = Lib.rng(field.seed);

            // nebulae: wide, faint radial glows
            var nebs = [field.neb1, field.neb2];
            for (var k = 0; k < 2; k++) {
                var nx = (0.2 + 0.6 * rnd()) * w, nr = 140 + rnd() * 160;
                var g = ctx.createRadialGradient(nx, h / 2, 0, nx, h / 2, nr);
                g.addColorStop(0, Lib.css(nebs[k], 0.075));
                g.addColorStop(1, Lib.css(nebs[k], 0));
                ctx.fillStyle = g;
                ctx.fillRect(nx - nr, 0, 2 * nr, h);
            }

            // galactic band: 35% of stars cluster around one x
            var band = (0.55 + 0.2 * rnd()) * w, spread = 0.1 * w;
            var n = Math.round(w * h / 110);
            for (var i = 0; i < n; i++) {
                var x;
                if (rnd() < 0.35) {               // Box–Muller
                    var u1 = Math.max(1e-9, rnd()), u2 = rnd();
                    x = band + spread * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
                } else {
                    x = rnd() * w;
                }
                var y = rnd() * h;
                var b = Math.pow(rnd(), 4);       // brightness: mostly faint
                var T = 2600 + Math.pow(rnd(), 2.2) * 14000;
                var a = 0.12 + 0.7 * b;
                var col = Lib.blackbody(T);

                if (b > 0.75) {                   // a few bright ones get a halo
                    ctx.fillStyle = Lib.hexA(col, 0.08);
                    ctx.beginPath(); ctx.arc(x, y, 3.2, 0, 2 * Math.PI); ctx.fill();
                    ctx.fillStyle = Lib.hexA(col, a);
                    ctx.beginPath(); ctx.arc(x, y, 1.1, 0, 2 * Math.PI); ctx.fill();
                } else {
                    var s = b > 0.25 ? 1.2 : 0.8;
                    ctx.fillStyle = Lib.hexA(col, a);
                    ctx.fillRect(Math.round(x), Math.round(y), s, s);
                }
            }
        }
    }

    // ---------------- meteor ----------------
    Timer {
        id: nextMeteor
        running: field.meteors && field.width > 0
        interval: 120000
        onTriggered: {
            field.shoot();
            interval = 90000 + Math.random() * 210000;   // every 1.5–5 min
            restart();
        }
    }

    function shoot() {
        var dx = 150 + Math.random() * 120;
        var dy = field.height + 10;
        meteor.rotation = Math.atan2(dy, dx) * 180 / Math.PI;
        fall.fromX = Math.random() * Math.max(1, field.width - dx) - meteor.width;
        fall.dx = dx;
        fall.restart();
    }

    Item {
        id: meteor
        visible: fall.running
        width: 60
        height: 1
        transformOrigin: Item.Right
        Rectangle {
            anchors.fill: parent
            radius: 0.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: field.theme.foreground }
            }
        }
    }

    ParallelAnimation {
        id: fall
        property real fromX: 0
        property real dx: 200
        NumberAnimation { target: meteor; property: "x"; from: fall.fromX; to: fall.fromX + fall.dx; duration: 650; easing.type: Easing.InQuad }
        NumberAnimation { target: meteor; property: "y"; from: -6; to: field.height + 4; duration: 650; easing.type: Easing.InQuad }
        SequentialAnimation {
            NumberAnimation { target: meteor; property: "opacity"; from: 0; to: 0.9; duration: 120 }
            PauseAnimation { duration: 330 }
            NumberAnimation { target: meteor; property: "opacity"; to: 0; duration: 200 }
        }
    }
}
