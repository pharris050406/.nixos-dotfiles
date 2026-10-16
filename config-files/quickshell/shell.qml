import Quickshell
import Quickshell.Wayland
import QtQuick

// DEEP FIELD
// A status bar that's a small piece of sky, with the physics done properly.
//
//  ★ G2 ◦ ◦ ●☾ ◦ ◯ ⊖ ◦      ◉ Track Title        21:36  22:14 lst        caution · gain · comms · mem · power
//  ▸━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▸· · · · · · · · · · · · · · · · · · · · · · · · · ◦
//
//  ★  your CPU is a star: load → surface temperature → true blackbody color
//     and spectral class. Hover it for its Planck spectrum against the Sun's.
//  ◦  workspaces are planets on fixed orbits. The focused one has a moon;
//     switching flies a probe between them. Hover for Kepler's numbers.
//  ◉  now playing is a transmission: track changes are Doppler-shifted.
//  ▸  the bottom edge is the song's flight path; click it to seek.
//     It turns red while the master caution lamp is lit.
//     the clock does UTC, sidereal time, MET and Julian date, and knows the Moon.
//     the instruments: nominal gain in dB, a comms scope + ping (LOS when
//     offline), memory as an orbit gauge, a battery cell on laptops.
//  ✦  behind it all, a seeded starfield, and now and then a meteor.
//  ›  scripts/dfmenu: a dmenu drawn by the bar (Picker.qml), for any script.
PanelWindow {
    id: bar

    // ---------------- settings ----------------
    // Ambient motion: the orbiting moon, radio pulse, comms scope, meteors,
    // Doppler and probe animations. Off on battery unless you change the second line.
    property bool motion: true
    property bool motionOnBattery: true
    // Translucent bar. Pairs with SwayFX: layer_effects "deepfield" blur enable
    property bool glass: false
    // Your location, for sidereal time and the Sun's altitude.
    property real latitude: 34.05
    property real longitude: -118.25
    // The live sky on the wallpaper layer. Set false to go back to a static image.
    property bool liveSky: true
    // Notifications for sky events over (latitude, longitude): close passes,
    // new and full moons, eclipses, meteor shower peaks, solstices/equinoxes.
    // Computed locally. The ephemeris card (hover the clock) lists them either way.
    property bool skyAlerts: true

    Theme { id: pal }

    readonly property bool moving: motion && (motionOnBattery || !Sys.discharging)
    Binding { target: Motion; property: "live"; value: bar.moving }
    Binding { target: Events; property: "latitude"; value: bar.latitude }
    Binding { target: Events; property: "longitude"; value: bar.longitude }
    Binding { target: Events; property: "notify"; value: bar.skyAlerts }

    anchors { top: true; left: true; right: true }
    implicitHeight: pal.fontSize + 21
    color: glass ? Qt.rgba(pal.background.r, pal.background.g, pal.background.b, pal.barOpacity) : pal.background
    WlrLayershell.namespace: "deepfield"

    Starfield {
        anchors.fill: parent
        theme: pal
        meteors: bar.moving
    }

    Item {
        id: content
        anchors { fill: parent; leftMargin: 8; rightMargin: 14; bottomMargin: 3 }

        Row {
            id: leftGroup
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            spacing: 18

            Orrery {
                theme: pal
                height: leftGroup.height
            }
            Transmission {
                id: transmission
                theme: pal
                anchors.verticalCenter: parent.verticalCenter
                // Never run into the clock.
                maxWidth: Math.max(0, chrono.x - leftGroup.x - transmission.x - 28)
            }
        }

        Chronometer {
            id: chrono
            theme: pal
            anchors.centerIn: parent
            latitude: bar.latitude
            longitude: bar.longitude
        }

        Telemetry {
            id: telemetry
            theme: pal
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            wifiOpen: wifi.visible
            // Center the Wi-Fi panel under the instruments (clamped to the screen).
            onWifiRequested: {
                var cx = telemetry.mapToItem(null, telemetry.width / 2, 0).x;
                var rm = bar.width - cx - wifi.implicitWidth / 2;
                wifi.toggle(Math.round(Math.max(0, Math.min(rm, bar.width - wifi.implicitWidth))));
            }
        }
    }

    Trajectory {
        theme: pal
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    // Notification popups (this bar is also the notification daemon).
    Signals {
        screen: bar.screen
        theme: pal
    }

    // Tonight's sky over (latitude, longitude), on the wallpaper layer.
    LazyLoader {
        active: bar.liveSky
        Sky {
            screen: bar.screen
            theme: pal
            latitude: bar.latitude
            longitude: bar.longitude
        }
    }

    // The bar's dmenu: scripts/dfmenu pipes lists in, gets the pick back.
    Picker {
        screen: bar.screen
        theme: pal
    }

    WifiPanel {
        id: wifi
        screen: bar.screen
        accentColor: pal.accent3
        textColor: pal.foreground
        mutedColor: pal.muted
        bgColor: pal.background
        warnColor: pal.accent6
        barColor: pal.barColor
        fontName: pal.fontFamily
        fontSize: pal.fontSize
    }
}
