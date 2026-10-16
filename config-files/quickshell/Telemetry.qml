import QtQuick
import Quickshell
import "Lib.js" as Lib

// Instrument cluster.
//   CAUTION  master caution lamp; names whatever is wrong, clears itself
//   GAIN     volume as nominal gain, 20·log₁₀(level). Wheel ±5, click mutes,
//            hover or any change unfolds the slider for a moment
//   COMMS    an oscilloscope carrier whose amplitude and frequency follow
//            throughput, then ping. Offline is LOS (loss of signal).
//            click: Wi-Fi panel   right-click: copy address
//   MEM      a satellite on an orbit gauge: the arc is how full memory is
//   POWER    battery cell (laptops only)
// Hover any of them for its card. CPU lives on the star, far left.
Row {
    id: tm

    property Theme theme
    property bool wifiOpen: false
    signal wifiRequested()

    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)
    readonly property int small: theme.fontSize - 1

    spacing: 16

    // ================= master caution =================
    readonly property var cautions: {
        var c = [];
        if (Net.offline) c.push("los");
        else if (Net.unreachable) c.push("no internet");
        if (Sys.cpuHot) c.push("cpu " + Sys.cpu + "%");
        if (Sys.memHot) c.push("mem " + Sys.mem + "%");
        if (Sys.batteryLow) c.push("power " + Sys.battery + "%");
        return c;
    }

    // Transient advisories: things that changed, said once.
    property string advisory: ""
    function advise(text) { advisory = text; advisoryT.restart(); }
    Timer { id: advisoryT; interval: 2800; onTriggered: tm.advisory = "" }
    Connections {
        target: Net
        function onSsidChanged() { if (Net.gotInfo && Net.ssid !== "") tm.advise("acquired " + Net.ssid); }
        function onOfflineChanged() { if (!Net.offline) tm.advise("signal reacquired"); }
        function onCopied(ok) { tm.advise(ok ? "copied " + Net.address : "copy failed: install wl-clipboard"); }
    }
    Connections {
        target: Sys
        function onBatteryFlagsChanged() {
            if (Sys.batteryKnown) tm.advise(Sys.batteryState + " · " + Sys.battery + "%");
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: implicitWidth > 0.5           // no gap when both lamps are dark
        spacing: 0
        Chip {
            theme: tm.theme
            anchors.verticalCenter: parent.verticalCenter
            on: tm.cautions.length > 0
            text: "caution · " + tm.cautions.join(" · ")
            ink: tm.theme.accent6
            pulse: Sys.batteryCritical || Net.offline
        }
        Chip {
            theme: tm.theme
            anchors.verticalCenter: parent.verticalCenter
            on: tm.advisory !== ""
            text: tm.advisory
            ink: tm.theme.accent2
        }
    }

    // ================= rx: notifications =================
    // "rx" quiet · "rx 3" unread (blue) · "rx off" radio silence
    // click: comms log   middle-click: radio silence   right-click: clear log
    Item {
        id: rx
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: rxText.implicitWidth
        implicitHeight: tm.theme.fontSize + 8

        Text {
            id: rxText
            anchors.verticalCenter: parent.verticalCenter
            text: Notifs.silence ? "rx off" : Notifs.unread > 0 ? "rx " + Notifs.unread : "rx"
            color: Notifs.silence ? tm.theme.muted : Notifs.unread > 0 ? tm.theme.accent2 : tm.label
            font { family: tm.theme.fontFamily; pixelSize: tm.small; bold: Notifs.unread > 0 && !Notifs.silence }
        }

        MouseArea {
            id: rxMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.RightButton) Notifs.clearHistory();
                else if (m.button === Qt.MiddleButton) Notifs.toggleSilence();
                else Notifs.logOpen = !Notifs.logOpen;
            }
        }

        // Closes itself once the pointer has left both "rx" and the log.
        Timer {
            running: Notifs.logOpen && !rxMouse.containsMouse && !logHover.hovered
            interval: 700
            onTriggered: Notifs.logOpen = false
        }

        PopupWindow {
            id: logPop
            visible: Notifs.logOpen
            color: "transparent"
            width: logBody.implicitWidth + 28
            height: logBody.implicitHeight + 30
            anchor {
                item: rx
                edges: Edges.Bottom | Edges.Right
                gravity: Edges.Bottom | Edges.Left
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(tm.theme.barColor.r, tm.theme.barColor.g, tm.theme.barColor.b, 1)
                border.width: 1
                border.color: Lib.mix(tm.theme.muted, tm.theme.barColor, 0.35)
                HoverHandler { id: logHover }

                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 2
                    color: Notifs.silence ? tm.theme.muted : tm.theme.accent2
                }

                Column {
                    id: logBody
                    x: 14; y: 16
                    width: 360
                    spacing: 8

                    Item {
                        width: parent.width
                        height: logHead.implicitHeight
                        Text {
                            id: logHead
                            text: "COMMS LOG"
                            color: Notifs.silence ? tm.theme.muted : tm.theme.accent2
                            font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 3; letterSpacing: 2.5; bold: true }
                        }
                        Row {
                            anchors { right: parent.right; baseline: logHead.baseline }
                            spacing: 14
                            Text {
                                text: Notifs.silence ? "radio silence: on" : "radio silence: off"
                                color: Notifs.silence ? tm.theme.accent4 : tm.label
                                font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 2; underline: silenceMouse.containsMouse }
                                MouseArea { id: silenceMouse; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor; onClicked: Notifs.toggleSilence() }
                            }
                            Text {
                                visible: Notifs.history.length > 0
                                text: "clear"
                                color: tm.label
                                font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 2; underline: clearMouse.containsMouse }
                                MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearHistory() }
                            }
                        }
                    }

                    Text {
                        visible: Notifs.history.length === 0
                        text: "no transmissions received"
                        color: tm.theme.muted
                        font { family: tm.theme.fontFamily; pixelSize: tm.small }
                    }

                    Repeater {
                        model: Notifs.history.slice(0, 12)
                        Row {
                            id: entry
                            required property var modelData
                            spacing: 10
                            Text {
                                width: 44
                                text: Qt.formatDateTime(new Date(entry.modelData.time), "HH:mm")
                                color: entry.modelData.critical ? tm.theme.accent6 : tm.label
                                font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 2 }
                            }
                            Column {
                                width: 306
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: ((entry.modelData.app ? entry.modelData.app + " · " : "") + entry.modelData.summary)
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: tm.theme.foreground
                                    font { family: tm.theme.fontFamily; pixelSize: tm.small }
                                }
                                Text {
                                    visible: text !== ""
                                    width: parent.width
                                    text: entry.modelData.body.replace(/\s+/g, " ")
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: tm.label
                                    font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 2 }
                                }
                            }
                        }
                    }

                    Text {
                        topPadding: 4
                        text: "click  log    middle-click  radio silence    right-click  clear"
                        color: tm.theme.muted
                        font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 3 }
                    }
                }
            }
        }
    }

    // ================= gain =================
    Item {
        id: gain
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: gainRow.implicitWidth
        implicitHeight: tm.theme.fontSize + 8
        readonly property bool open: gainHover.containsMouse || Audio.dragging || reveal.running
        readonly property int trackW: 60

        Timer { id: reveal; interval: 1800 }
        Connections {
            target: Audio
            function onExternalChange() { reveal.restart(); }
        }

        MouseArea {
            id: gainHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onWheel: w => { Audio.setVolume(Audio.volume + (w.angleDelta.y > 0 ? 5 : -5)); reveal.restart(); }
        }

        Row {
            id: gainRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: gain.open ? gain.trackW : 0
                height: gain.implicitHeight
                visible: width > 0.5
                clip: true
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: gain.trackW; height: 2; radius: 1
                    color: Lib.mix(tm.theme.muted, tm.theme.background, 0.3)
                }
                Rectangle {
                    id: lvl
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(gain.trackW * Audio.volume / 100); height: 2; radius: 1
                    color: Audio.muted ? tm.theme.muted : tm.theme.accent4
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(gain.trackW - width, lvl.width - 1))
                    width: 2; height: 10; radius: 1
                    color: Audio.muted ? tm.theme.muted : tm.theme.foreground
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function setFrom(x) { Audio.setVolume(Math.round(Lib.clamp01(x / width) * 20) * 5); }
                    onPressed: m => { Audio.dragging = true; setFrom(m.x); }
                    onPositionChanged: m => { if (pressed) setFrom(m.x); }
                    onReleased: { Audio.dragging = false; reveal.restart(); }
                    onCanceled: Audio.dragging = false
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Audio.muted ? "󰝟" : Audio.volume === 0 ? "󰕿" : Audio.volume < 50 ? "󰖀" : "󰕾"
                color: Audio.muted ? tm.theme.muted : gain.open ? tm.theme.accent4 : tm.theme.foreground
                font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize + 1 }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Audio.toggleMute(); reveal.restart(); }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Audio.muted ? "mute" : Lib.gainDb(Audio.volume / 100)
                color: Audio.muted ? tm.label : tm.theme.foreground
                font { family: tm.theme.fontFamily; pixelSize: tm.small }
            }
        }
    }

    // ================= comms =================
    Item {
        id: comms
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: commsRow.implicitWidth
        implicitHeight: tm.theme.fontSize + 8
        readonly property bool los: Net.offline || Net.unreachable

        Row {
            id: commsRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Canvas {
                id: scope
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 14

                // What the data says (it updates once a second)...
                readonly property real targetAmp: comms.los ? 0 : Net.activity
                readonly property real targetLost: comms.los ? 1 : 0
                // ...and what's drawn, easing toward it (time constant 0.4 s), so a
                // traffic change swells or settles the wave instead of snapping it.
                property real amp: 0
                property real freq: 0                  // eases slower than amp (0.9 s)
                property real lost: 0
                // Phase is integrated (phase += dt × speed) rather than computed as
                // t × speed: with the old way, any change in speed made the whole
                // wave jump to a different phase.
                property real phase: 0
                property real lastT: -1
                readonly property bool settling: Math.abs(amp - targetAmp) > 0.002 || Math.abs(freq - targetAmp) > 0.002
                                                 || Math.abs(lost - targetLost) > 0.002
                readonly property bool moving: Motion.live && (amp > 0.02 || settling)
                onMovingChanged: lastT = -1            // don't integrate across a pause

                Connections {
                    target: Motion
                    enabled: scope.moving
                    function onTChanged() { scope.step(); }
                }
                function step() {
                    var t = Motion.t;
                    var dt = lastT < 0 ? 0.05 : Math.max(0, Math.min(0.2, t - lastT));
                    lastT = t;
                    var e = 1 - Math.exp(-dt / 0.4);
                    amp += (targetAmp - amp) * e;
                    freq += (targetAmp - freq) * (1 - Math.exp(-dt / 0.9));
                    lost += (targetLost - lost) * e;
                    phase = (phase + dt * (3 + 6 * amp)) % (2 * Math.PI);
                    requestPaint();
                }
                // Motion off (on battery): no animation, just show the new state.
                onTargetAmpChanged: if (!Motion.live) { amp = targetAmp; freq = targetAmp; requestPaint(); }
                onTargetLostChanged: if (!Motion.live) { lost = targetLost; requestPaint(); }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var mid = height / 2, W = width;
                    ctx.fillStyle = Lib.css(tm.theme.muted, 0.35);
                    ctx.fillRect(0, Math.round(mid), W, 1);
                    ctx.lineWidth = 1.2;
                    ctx.strokeStyle = Lib.mix(tm.theme.accent3, tm.theme.accent6, lost);
                    var A = (0.6 + 5.4 * amp) * (1 - lost);
                    // Anchored at the center, so a frequency change stretches the wave
                    // symmetrically instead of whipping its far end around.
                    var k = (1.5 + 2 * freq) * 2 * Math.PI / W;
                    ctx.beginPath();
                    for (var x = 0; x <= W; x++) {
                        // a soft envelope: the signal tapers toward the edges
                        var env = 0.35 + 0.65 * Math.sin(Math.PI * x / W);
                        var y = mid - A * env * Math.sin(k * (x - W / 2) - phase);
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: comms.los ? "LOS" : Net.pingMs < 0 ? "— ms" : Math.round(Net.pingMs) + " ms"
                color: comms.los ? tm.theme.accent6 : tm.theme.foreground
                font { family: tm.theme.fontFamily; pixelSize: tm.small; bold: comms.los }
            }
        }

        MouseArea {
            id: commsMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.RightButton) Net.copyAddress();
                else tm.wifiRequested();
            }
        }

        Card {
            id: commsCard
            theme: tm.theme
            target: comms
            alignRight: true
            accent: comms.los ? tm.theme.accent6 : tm.theme.accent3
            heading: "comms"
            subheading: Net.offline ? "loss of signal" : (Net.iface || "…") + (Net.ssid ? " · " + Net.ssid : "")
            want: commsMouse.containsMouse && !tm.wifiOpen

            readonly property real oneWay: Net.pingMs > 0 ? Lib.lightDistance(Net.pingMs / 2000) : 0

            Loader {
                active: commsCard.visible
                sourceComponent: Column {
                    spacing: 6
                    Trace { theme: tm.theme; name: "down"; values: Net.downHistory
                            tint: tm.theme.accent3; value: Lib.bytes(Net.down) + "/s" }
                    Trace { theme: tm.theme; name: "up"; values: Net.upHistory
                            tint: tm.theme.accent4; value: Lib.bytes(Net.up) + "/s" }
                    Trace { theme: tm.theme; name: "ping"; values: Net.pingHistory
                            tint: tm.theme.accent2
                            value: Net.pingMs < 0 ? "timeout" : Net.pingMs.toFixed(1) + " ms"
                            hot: Net.gotInfo && !Net.offline && Net.pingMs < 0 }
                    Readout { theme: tm.theme; k: "address"; v: Net.address }
                    Readout { theme: tm.theme; k: "gateway"; v: Net.gateway || "…" }
                    Readout {
                        visible: commsCard.oneWay > 0
                        theme: tm.theme; k: "light path"
                        v: Lib.distance(commsCard.oneWay) + " one-way at c"
                    }
                    Readout {
                        visible: commsCard.oneWay > 0
                        theme: tm.theme; k: ""; dim: true
                        v: (commsCard.oneWay / Lib.MOON_DIST * 100).toFixed(2) + "% of the way to the moon"
                    }
                    Readout { theme: tm.theme; k: "total"
                              v: "▼ " + Lib.bytes(Net.rxTotal) + "   ▲ " + Lib.bytes(Net.txTotal) }
                    Readout { theme: tm.theme; k: "peak"
                              v: "▼ " + Lib.bytes(Net.downPeak) + "/s   ▲ " + Lib.bytes(Net.upPeak) + "/s" }
                    Text {
                        topPadding: 4
                        text: "click  wi-fi    right-click  copy address"
                        color: tm.theme.muted
                        font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 3 }
                    }
                }
            }
        }
    }

    // ================= memory =================
    Item {
        id: mem
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: memRow.implicitWidth
        implicitHeight: tm.theme.fontSize + 8

        Row {
            id: memRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Canvas {
                id: orbitGauge
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                property real f: Sys.mem / 100
                property bool hot: Sys.memHot
                onFChanged: requestPaint()
                onHotChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var c = width / 2, r = c - 2.2;
                    var a0 = -Math.PI / 2, a1 = a0 + 2 * Math.PI * Lib.clamp01(f);
                    ctx.lineWidth = 1.2;
                    ctx.strokeStyle = Lib.css(tm.theme.muted, 0.45);
                    ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke();
                    ctx.lineWidth = 1.8;
                    ctx.strokeStyle = Lib.css(hot ? tm.theme.accent6 : tm.theme.accent7, 1);
                    ctx.beginPath(); ctx.arc(c, c, r, a0, a1, false); ctx.stroke();
                    ctx.fillStyle = Lib.css(tm.theme.muted, 0.9);              // the planet
                    ctx.beginPath(); ctx.arc(c, c, 1.6, 0, 2 * Math.PI); ctx.fill();
                    ctx.fillStyle = Lib.css(tm.theme.foreground, 1);           // the satellite
                    ctx.beginPath(); ctx.arc(c + r * Math.cos(a1), c + r * Math.sin(a1), 1.7, 0, 2 * Math.PI); ctx.fill();
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Sys.mem + "%"
                color: Sys.memHot ? tm.theme.accent6 : tm.theme.foreground
                font { family: tm.theme.fontFamily; pixelSize: tm.small }
            }
        }

        MouseArea { id: memMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true }

        Card {
            id: memCard
            theme: tm.theme
            target: mem
            alignRight: true
            accent: Sys.memHot ? tm.theme.accent6 : tm.theme.accent7
            heading: "memory"
            subheading: Lib.bytes(Sys.memUsed) + " of " + Lib.bytes(Sys.memTotal)
            want: memMouse.containsMouse

            readonly property real joules: Lib.landauerJoules(Sys.memUsed, 300)

            Loader {
                active: memCard.visible
                sourceComponent: Column {
                    spacing: 6
                    Trace { theme: tm.theme; name: "used"; values: Sys.memHistory
                            tint: tm.theme.accent7; value: Sys.mem + "%"; hot: Sys.memHot }
                    Readout { theme: tm.theme; k: "erase it"
                              v: "≥ " + Lib.sci(memCard.joules, 2) + " J at 300 K" }
                    Readout { theme: tm.theme; k: ""; dim: true
                              v: "≈ " + (memCard.joules / (Lib.C * Lib.C) / Lib.PROTON).toFixed(2) + " proton masses of energy" }
                    Text {
                        topPadding: 4
                        text: "landauer limit: erasing one bit costs at least kT ln 2"
                        color: tm.theme.muted
                        font { family: tm.theme.fontFamily; pixelSize: tm.theme.fontSize - 3 }
                    }
                }
            }
        }
    }

    // ================= power (laptops) =================
    Item {
        id: power
        visible: Sys.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: powerRow.implicitWidth
        implicitHeight: tm.theme.fontSize + 8
        readonly property color ink: Sys.batteryLow ? tm.theme.accent6 : Sys.charging ? tm.theme.accent3 : tm.theme.accent1

        Row {
            id: powerRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 9
                Rectangle {
                    width: 16; height: 9; radius: 2
                    color: "transparent"
                    border.width: 1
                    border.color: Lib.mix(tm.theme.foreground, tm.theme.muted, 0.4)
                    Rectangle {
                        x: 2; y: 2
                        width: Math.max(1, Math.round(12 * Sys.battery / 100)); height: 5; radius: 1
                        color: power.ink
                        SequentialAnimation on opacity {
                            running: Sys.batteryCritical
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }
                }
                Rectangle {
                    x: 16; y: 3; width: 2; height: 3; radius: 1
                    color: Lib.mix(tm.theme.foreground, tm.theme.muted, 0.4)
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Sys.battery + "%" + (Sys.charging ? "+" : "")
                color: Sys.batteryLow ? tm.theme.accent6 : tm.theme.foreground
                font { family: tm.theme.fontFamily; pixelSize: tm.small }
            }
        }

        MouseArea { id: powerMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true }

        Card {
            theme: tm.theme
            target: power
            alignRight: true
            accent: power.ink
            heading: "power"
            subheading: Sys.batteryState
            want: powerMouse.containsMouse

            Readout { theme: tm.theme; k: "charge"; v: Sys.battery + "%"; hot: Sys.batteryLow }
            Readout {
                theme: tm.theme; k: "remaining"
                v: Sys.discharging && Sys.batteryMinutes >= 0 ? Lib.minutes(Sys.batteryMinutes) : "—"
            }
        }
    }
}
