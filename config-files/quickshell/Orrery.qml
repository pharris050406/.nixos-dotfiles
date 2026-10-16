import QtQuick
import Quickshell
import Quickshell.I3
import "Lib.js" as Lib

// Workspaces as a planetary system, seen from above.
//
// The STAR is your CPU. Load sets its surface temperature on a log scale
// (idle 2,000 K, flat out 40,000 K) and it's drawn in the true blackbody color
// for that temperature, labeled with its Harvard spectral class. Idle, it's a
// dim orange brown dwarf; compiling, a blue-white B star swelling into a giant.
//
// The PLANETS are workspaces 1–10 on fixed orbits, Mercury through Eris, each
// lit from the star's side. Empty workspaces leave an empty orbit. The focused
// one gets a moon; switching workspace flies a probe between the two worlds.
// Urgent ones flare red.
//
//   click a planet: go there   wheel: next/previous   hover: orbital elements
//   hover the star: its spectrum (Planck curve vs. the Sun)
Item {
    id: orrery

    property Theme theme

    readonly property int slots: 10
    readonly property int slotW: theme.fontSize + 11
    readonly property real starX: 10
    readonly property real firstR: 32
    readonly property real cy: height / 2
    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)

    implicitWidth: starX + firstR + (slots - 1) * slotW + 14
    implicitHeight: 30

    function orbitR(i) { return firstR + i * slotW; }
    function planetX(i) { return starX + orbitR(i); }

    // ---------------- workspace state ----------------
    readonly property var present: {
        var a = [];
        for (const w of I3.workspaces.values)
            if (w.number >= 1 && w.number <= slots) a.push(w.number - 1);
        return a.sort((x, y) => x - y);
    }
    readonly property string presentKey: present.join(",")
    onPresentKeyChanged: orbits.requestPaint()

    readonly property int focusedIdx: {
        var w = I3.workspaces.values.find(w => w.focused);
        return w && w.number >= 1 && w.number <= slots ? w.number - 1 : -1;
    }

    // Probe transfer between the old and new focused worlds.
    property int lastFocus: -1
    property bool settled: false
    Component.onCompleted: Qt.callLater(() => { settled = true; lastFocus = focusedIdx; })
    onFocusedIdxChanged: {
        if (settled && Motion.live && lastFocus >= 0 && focusedIdx >= 0 && lastFocus !== focusedIdx) {
            transfer.fromX = planetX(lastFocus);
            transfer.toX = planetX(focusedIdx);
            transfer.restart();
        }
        lastFocus = focusedIdx;
    }

    // ---------------- orbits ----------------
    // Arcs of circles centered on the star, clipped to the bar's height.
    Canvas {
        id: orbits
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 1;
            for (var i = 0; i < orrery.slots; i++) {
                var r = orrery.orbitR(i);
                var th = Math.asin(Math.min(1, (height / 2 + 2) / r));
                ctx.strokeStyle = Lib.css(orrery.theme.muted, orrery.present.indexOf(i) >= 0 ? 0.5 : 0.18);
                ctx.beginPath();
                ctx.arc(orrery.starX, orrery.cy, r, -th, th, false);
                ctx.stroke();
            }
        }
    }

    // ---------------- the star (cpu) ----------------
    readonly property real kelvin: Lib.loadToKelvin(Sys.cpuSmooth)
    readonly property string starColor: Lib.blackbody(kelvin)
    readonly property string spectral: Lib.spectralClass(kelvin)
    readonly property string lumClass: Lib.luminosityClass(Sys.cpuSmooth)

    Canvas {
        id: star
        width: 34; height: 34
        x: orrery.starX - width / 2
        y: orrery.cy - height / 2
        // Quantized to ~2% steps in temperature: the eased load changes a little
        // every second, and redrawing the bar for invisible changes costs power.
        property int k: Math.round(Math.log(orrery.kelvin) * 50)
        onKChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var c = width / 2, load = Sys.cpuSmooth, col = orrery.starColor;
            var R = 3.2 + 3.6 * load;             // swells with load
            var glow = ctx.createRadialGradient(c, c, 0, c, c, R * 2.4);
            glow.addColorStop(0, Lib.hexA(col, 0.5));
            glow.addColorStop(0.45, Lib.hexA(col, 0.16));
            glow.addColorStop(1, Lib.hexA(col, 0));
            ctx.fillStyle = glow;
            ctx.fillRect(0, 0, width, height);
            var core = ctx.createRadialGradient(c - R * 0.3, c - R * 0.3, 0, c, c, R);
            core.addColorStop(0, "rgba(255,255,255,0.95)");
            core.addColorStop(1, Lib.hexA(col, 1));
            ctx.fillStyle = core;
            ctx.beginPath();
            ctx.arc(c, c, R, 0, 2 * Math.PI);
            ctx.fill();
        }
    }
    Text {
        x: orrery.starX + 8
        y: orrery.cy - height - 2
        text: orrery.spectral
        color: orrery.starColor
        font { family: orrery.theme.fontFamily; pixelSize: orrery.theme.fontSize - 4; bold: true }
    }
    MouseArea {
        id: starMouse
        x: 0; width: orrery.starX + 18
        height: parent.height
        hoverEnabled: true
    }

    // ---------------- planets ----------------
    property int hovered: -1
    property int shownPlanet: 0
    onHoveredChanged: if (hovered >= 0) shownPlanet = hovered

    // The focused world's moon: one orbit per 8 s, in front of the planet on
    // the near side, behind it on the far side.
    readonly property real moonAngle: Motion.live ? Motion.t * 2 * Math.PI / 8 : -2.2

    Repeater {
        id: rep
        model: orrery.slots

        Item {
            id: world
            required property int index
            readonly property var info: Lib.PLANETS[index]
            readonly property var ws: I3.workspaces.values.find(w => w.number === index + 1)
            readonly property bool exists: ws !== undefined
            readonly property bool focused: ws ? ws.focused : false
            readonly property bool urgent: ws ? ws.urgent : false
            readonly property real r: info.r
            readonly property real cx: width / 2

            x: orrery.planetX(index) - width / 2
            width: orrery.slotW
            height: orrery.height

            // flare / focus halo
            Rectangle {
                visible: world.exists && (world.focused || world.urgent)
                anchors.centerIn: body
                width: world.r * 2 + 8; height: width; radius: width / 2
                color: world.urgent ? orrery.theme.accent6 : orrery.theme.accent1
                opacity: world.urgent ? 0.45 : 0.18
                SequentialAnimation on opacity {
                    running: world.urgent && !world.focused
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.08; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.5;  duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // Saturn's ring
            Rectangle {
                visible: world.exists && world.info.ring === true
                anchors.centerIn: body
                width: world.r * 4.4; height: 3.5; radius: height / 2
                rotation: -18
                color: "transparent"
                border.width: 1
                border.color: Lib.hexA(world.info.tint, world.focused ? 0.9 : 0.45)
            }

            // the planet, lit from the star's side (left)
            Rectangle {
                id: body
                visible: world.exists
                x: world.cx - world.r
                y: orrery.cy - world.r
                width: world.r * 2; height: width; radius: world.r
                readonly property string lit: world.focused ? world.info.tint
                    : Lib.mix(Qt.color(world.info.tint), orrery.theme.muted, 0.5)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: body.lit }
                    GradientStop { position: 1.0; color: Lib.mix(Qt.color(body.lit), orrery.theme.background, 0.6) }
                }
            }

            // moon (focused world only)
            Rectangle {
                readonly property real d: world.r + 5
                visible: world.exists && world.focused && !transfer.running
                width: 3; height: 3; radius: 1.5
                x: world.cx + d * Math.cos(orrery.moonAngle) - 1.5
                y: orrery.cy + 0.38 * d * Math.sin(orrery.moonAngle) - 1.5
                z: Math.sin(orrery.moonAngle) > 0 ? 2 : -1
                color: orrery.theme.foreground
                opacity: z > 0 ? 1 : 0.5
            }

            // designation
            Text {
                visible: world.exists
                x: world.cx + world.r + 1
                y: orrery.cy - world.r - height + 4
                text: world.index + 1
                color: world.urgent ? orrery.theme.accent6
                     : world.focused ? orrery.theme.foreground : orrery.label
                font { family: orrery.theme.fontFamily; pixelSize: orrery.theme.fontSize - 4; bold: world.focused }
            }

            MouseArea {
                anchors.fill: parent
                enabled: world.exists
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: {
                    if (containsMouse) orrery.hovered = world.index;
                    else if (orrery.hovered === world.index) orrery.hovered = -1;
                }
                onClicked: I3.dispatch("workspace number " + (world.index + 1))
            }
        }
    }

    // ---------------- probe ----------------
    // Half an ellipse between the two worlds: a cartoon Hohmann transfer.
    Item {
        id: probe
        property real t: 0
        visible: transfer.running
        x: transfer.fromX + (transfer.toX - transfer.fromX) * t - 1.5
        y: orrery.cy - 10 * Math.sin(Math.PI * t) - 1.5
        width: 3; height: 3
        z: 5
        Rectangle { anchors.fill: parent; radius: 1.5; color: orrery.theme.foreground }
    }
    NumberAnimation {
        id: transfer
        property real fromX: 0
        property real toX: 0
        target: probe; property: "t"; from: 0; to: 1
        duration: 340; easing.type: Easing.InOutSine
    }

    // Wheel over the system (buttons fall through).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: w => I3.dispatch(w.angleDelta.y > 0 ? "workspace prev_on_output" : "workspace next_on_output")
    }

    // ---------------- cards ----------------
    Card {
        id: planetCard
        theme: orrery.theme
        target: rep.count > orrery.shownPlanet ? rep.itemAt(orrery.shownPlanet) : orrery
        accent: Qt.color(Lib.PLANETS[orrery.shownPlanet].tint)
        heading: "workspace " + (orrery.shownPlanet + 1)
        subheading: Lib.PLANETS[orrery.shownPlanet].name
        want: orrery.hovered >= 0

        readonly property real a: Lib.PLANETS[orrery.shownPlanet].a
        Readout { theme: orrery.theme; k: "semi-major"; v: planetCard.a.toFixed(3) + " AU" }
        Readout { theme: orrery.theme; k: "period"; v: Lib.years(Lib.orbitalPeriod(planetCard.a)) + "   (T² = a³)" }
        Readout { theme: orrery.theme; k: "sunlight"; v: Lib.hm(planetCard.a * Lib.AU / Lib.C) + " old on arrival" }
    }

    Card {
        id: starCard
        theme: orrery.theme
        target: star
        accent: Qt.color(orrery.starColor)
        heading: "stellar class"
        subheading: "cpu " + Sys.cpu + "%"
        want: starMouse.containsMouse

        Loader {
            active: starCard.visible
            sourceComponent: Column {
                spacing: 6

                Canvas {
                    id: spectrum
                    width: 340; height: 104
                    property real k: orrery.kelvin
                    onKChanged: requestPaint()

                    readonly property real lo: 100e-9
                    readonly property real hi: 2500e-9
                    readonly property int n: 170
                    function xOf(lambda) { return (lambda - spectrum.lo) / (spectrum.hi - spectrum.lo) * spectrum.width; }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var W = width, base = height - 14, top = 6, hgt = base - top;
                        var T = orrery.kelvin, col = orrery.starColor;
                        var lo = spectrum.lo, hi = spectrum.hi, n = spectrum.n;
                        var cur = Lib.planckCurve(T, lo, hi, n);
                        var sun = Lib.planckCurve(Lib.SUN_T, lo, hi, n);
                        function px(i) { return i / (n - 1) * W; }
                        function py(v) { return base - v * hgt; }
                        function trace(vals) {
                            ctx.beginPath();
                            for (var i = 0; i < n; i++) {
                                if (i === 0) ctx.moveTo(px(i), py(vals[i])); else ctx.lineTo(px(i), py(vals[i]));
                            }
                        }

                        // area under the curve
                        trace(cur);
                        ctx.lineTo(W, base); ctx.lineTo(0, base); ctx.closePath();
                        ctx.fillStyle = Lib.hexA(col, 0.14);
                        ctx.fill();

                        // the visible band, under the curve, in its actual colors
                        var x0 = xOf(380e-9), x1 = xOf(750e-9);
                        var rainbow = ctx.createLinearGradient(x0, 0, x1, 0);
                        var stops = [[0, "#7a00ff"], [0.19, "#2040ff"], [0.31, "#00b4ff"], [0.38, "#20d040"],
                                     [0.51, "#e8e800"], [0.57, "#ff9a00"], [0.65, "#ff2a1a"], [1, "#7a0000"]];
                        for (var s = 0; s < stops.length; s++) rainbow.addColorStop(stops[s][0], stops[s][1]);
                        ctx.save();
                        ctx.beginPath();
                        ctx.rect(x0, 0, x1 - x0, height);
                        ctx.clip();
                        trace(cur);
                        ctx.lineTo(W, base); ctx.lineTo(0, base); ctx.closePath();
                        ctx.globalAlpha = 0.55;
                        ctx.fillStyle = rainbow;
                        ctx.fill();
                        ctx.restore();

                        // the Sun, for reference
                        trace(sun);
                        ctx.lineWidth = 1;
                        ctx.strokeStyle = Lib.css(orrery.theme.muted, 0.9);
                        ctx.stroke();

                        // this star
                        trace(cur);
                        ctx.lineWidth = 1.8;
                        ctx.strokeStyle = Lib.hexA(col, 1);
                        ctx.stroke();

                        // Wien peak
                        var peak = Lib.wienPeakNm(T) * 1e-9;
                        if (peak > lo && peak < hi) {
                            ctx.fillStyle = Lib.css(orrery.theme.foreground, 0.6);
                            ctx.fillRect(Math.round(xOf(peak)), top, 1, hgt);
                        }

                        // axis
                        ctx.fillStyle = Lib.css(orrery.theme.muted, 0.8);
                        ctx.fillRect(0, base, W, 1);
                        ctx.font = (orrery.theme.fontSize - 4) + "px '" + orrery.theme.fontFamily + "'";
                        ctx.textAlign = "center";
                        for (var nm = 500; nm <= 2000; nm += 500) {
                            var tx = xOf(nm * 1e-9);
                            ctx.fillRect(Math.round(tx), base, 1, 3);
                            ctx.fillText(nm + " nm", tx, height - 1);
                        }
                    }
                }

                Readout { theme: orrery.theme; k: "class"
                          v: orrery.spectral + " " + orrery.lumClass + "   " + Lib.luminosityName(orrery.lumClass) }
                Readout { theme: orrery.theme; k: "surface"; v: Lib.grouped(orrery.kelvin) + " K" }
                Readout {
                    theme: orrery.theme; k: "peak λ"
                    readonly property real nm: Lib.wienPeakNm(orrery.kelvin)
                    v: Math.round(nm) + " nm   " + (nm < 380 ? "ultraviolet" : nm > 750 ? "infrared" : "visible")
                }
                Readout { theme: orrery.theme; k: "vs. sun"; dim: true
                          v: "grey curve: 5,772 K, G2 V" }
                Trace { theme: orrery.theme; name: "load"; values: Sys.cpuHistory
                        tint: Qt.color(orrery.starColor); value: Sys.cpu + "%"; hot: Sys.cpuHot }
                Text {
                    topPadding: 2
                    text: "temperature = 2,000 K · 20^load   (Wien: λmax = b / T)"
                    color: orrery.theme.muted
                    font { family: orrery.theme.fontFamily; pixelSize: orrery.theme.fontSize - 3 }
                }
            }
        }
    }
}
