import QtQuick
import Quickshell
import Quickshell.Io
import "Lib.js" as Lib

// 21:36  tue 13 oct
// Click cycles the second readout: date → UTC → local sidereal → MET → Julian date.
// Hover for the ephemeris: every clock at once, the Moon's phase (drawn),
// whether the Sun is far enough down for dark skies, and what's coming up in
// the sky this week (Events.qml).
Item {
    id: chrono

    property Theme theme
    property real latitude: 34.05
    property real longitude: -118.25

    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    FileView {
        path: Quickshell.statePath("chronometer.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: saved
            property int mode: 0
        }
    }

    property var now: new Date()
    readonly property real jd: Lib.julian(now.getTime())

    // Once a minute, on the minute; once a second while the card is open.
    Timer {
        id: tick
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 1000
        onTriggered: {
            chrono.now = new Date();
            var ms = Date.now();
            interval = card.visible ? 1000 - ms % 1000 : 60000 - ms % 60000;
        }
    }

    readonly property string utc: Lib.pad(now.getUTCHours(), 2) + ":" + Lib.pad(now.getUTCMinutes(), 2)
    readonly property string second: [
        Qt.formatDateTime(now, "ddd d MMM").toLowerCase(),
        utc + " utc",
        Lib.hours(Lib.lst(jd, longitude)) + " lst",
        Lib.met(Sys.uptime()).slice(0, 13).toLowerCase(),
        "jd " + jd.toFixed(2)
    ][saved.mode % 5]

    Row {
        id: row
        spacing: 10
        Text {
            anchors.baseline: sub.baseline
            text: Qt.formatDateTime(chrono.now, "HH:mm")
            color: chrono.theme.foreground
            font { family: chrono.theme.fontFamily; pixelSize: chrono.theme.fontSize; bold: true }
        }
        Text {
            id: sub
            text: chrono.second
            color: chrono.label
            font { family: chrono.theme.fontFamily; pixelSize: chrono.theme.fontSize - 1 }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { saved.mode = (saved.mode + 1) % 5; tick.restart(); }
    }

    // "today", "tomorrow", "sat 24"
    function dayLabel(ms) {
        var d = new Date(ms), n = chrono.now;
        var dd = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate())
                             - new Date(n.getFullYear(), n.getMonth(), n.getDate())) / 86400000);
        return dd === 0 ? "today" : dd === 1 ? "tomorrow" : Qt.formatDateTime(d, "ddd d").toLowerCase();
    }

    // ---------------- ephemeris ----------------
    readonly property var lunar: Lib.moon(jd)
    readonly property var solar: Lib.sun(jd, latitude, longitude)

    Card {
        id: card
        theme: chrono.theme
        target: chrono
        accent: chrono.theme.accent4
        heading: "ephemeris"
        subheading: Math.abs(chrono.latitude).toFixed(2) + "°" + (chrono.latitude >= 0 ? "N " : "S ")
                  + Math.abs(chrono.longitude).toFixed(2) + "°" + (chrono.longitude >= 0 ? "E" : "W")
        want: mouse.containsMouse
        onVisibleChanged: tick.restart()        // retune to 1 s / 60 s right away

        Readout { theme: chrono.theme; k: "local"
                  v: Qt.formatDateTime(chrono.now, "HH:mm:ss   ddd d MMM yyyy").toLowerCase() }
        Readout { theme: chrono.theme; k: "utc"
                  v: Lib.hours(chrono.now.getUTCHours() + chrono.now.getUTCMinutes() / 60 + chrono.now.getUTCSeconds() / 3600, true) }
        Readout { theme: chrono.theme; k: "sidereal"
                  v: Lib.hours(Lib.lst(chrono.jd, chrono.longitude), true) + " lst" }
        Readout { theme: chrono.theme; k: "julian"; v: chrono.jd.toFixed(5) }
        Readout { theme: chrono.theme; k: "mission"; v: Lib.met(Sys.uptime()) }

        Item { width: 1; height: 2 }

        Row {
            spacing: 12
            Canvas {
                id: moonDisk
                width: 38; height: 38
                property real phase: chrono.lunar.phase
                onPhaseChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var c = width / 2, r = c - 2, p = phase;
                    var lit = Lib.css(chrono.theme.foreground, 0.92);
                    var dark = Lib.mix(chrono.theme.muted, chrono.theme.background, 0.55);
                    ctx.fillStyle = dark;                         // the whole disk, unlit
                    ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.fill();
                    ctx.fillStyle = lit;                          // the lit half
                    ctx.beginPath();
                    if (p < 0.5) ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, false);   // waxing: right
                    else ctx.arc(c, c, r, Math.PI / 2, 3 * Math.PI / 2, false);         // waning: left
                    ctx.fill();
                    // terminator: an ellipse that either eats the lit half (crescent)
                    // or extends it (gibbous)
                    var k = Math.cos(2 * Math.PI * p), rx = Math.abs(k) * r;
                    ctx.fillStyle = k > 0 ? dark : lit;
                    ctx.beginPath();
                    ctx.ellipse(c - rx, c - r, 2 * rx, 2 * r);
                    ctx.fill();
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: chrono.lunar.name
                    color: chrono.theme.foreground
                    font { family: chrono.theme.fontFamily; pixelSize: chrono.theme.fontSize - 1 }
                }
                Text {
                    text: chrono.lunar.age.toFixed(1) + " days old · " + Math.round(chrono.lunar.illum * 100) + "% lit"
                    color: chrono.label
                    font { family: chrono.theme.fontFamily; pixelSize: chrono.theme.fontSize - 2 }
                }
            }
        }

        Readout {
            theme: chrono.theme; k: "sun"
            v: (chrono.solar.alt >= 0 ? "+" : "−") + Math.abs(chrono.solar.alt).toFixed(1) + "°   " + Lib.twilight(chrono.solar.alt)
               + (chrono.solar.alt < -18 ? ", deep-sky ok" : "")
        }

        Text {
            visible: Events.ahead.length > 0
            topPadding: 8
            text: "UPCOMING"
            color: chrono.theme.accent4
            font { family: chrono.theme.fontFamily; pixelSize: chrono.theme.fontSize - 3; letterSpacing: 2.5; bold: true }
        }
        Repeater {
            model: Events.ahead.slice(0, 5)
            Readout {
                required property var modelData
                theme: chrono.theme
                k: chrono.dayLabel(modelData.ms)
                v: Qt.formatDateTime(new Date(modelData.ms), "HH:mm") + "  " + modelData.title.toLowerCase()
                dim: !modelData.notify
            }
        }
        Text {
            topPadding: 4
            text: "click: cycle date / utc / lst / met / jd"
            color: chrono.theme.muted
            font { family: chrono.theme.fontFamily; pixelSize: chrono.theme.fontSize - 3 }
        }
    }
}
