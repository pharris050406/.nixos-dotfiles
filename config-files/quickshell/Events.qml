pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "SkyEvents.js" as EV

// What's coming up in the sky over (latitude, longitude), worked out here
// from the same orbits the live sky uses. No downloads.
//   close passes of the Moon, planets and bright ecliptic stars (and the
//   Moon covering one), new and full moons, eclipses visible from here,
//   meteor shower peaks, solstices and equinoxes.
//
//   upcoming   the next 8 days, rescanned hourly (about 10 ms of maths)
//   ahead      the ones still in the future
//   notify     announce each one once, as a notification: four hours ahead,
//              or at 20:00 the evening before for anything before 8 a.m.
//              Remembered across restarts, so a config reload never repeats one.
//
//   qs ipc call sky list       what's coming, as text (* = will be announced)
//   qs ipc call sky preview    pop up the next announcement now, to try it out
//                              (it still comes at its proper time too)
Singleton {
    id: events

    property real latitude: 34.05
    property real longitude: -118.25
    property bool notify: true
    readonly property int days: 8

    property var upcoming: []
    property real now: Date.now()
    property real scannedAt: 0
    readonly property var ahead: upcoming.filter(e => e.ms > now)

    function scan() {
        var t = Date.now();
        try {
            upcoming = EV.upcoming(t, days, latitude, longitude);
        } catch (err) {
            console.warn("deepfield sky events:", err);
            upcoming = [];
        }
        scannedAt = t;
    }

    function check() {
        now = Date.now();
        // Hourly, and whenever the date changes: the texts say "tonight".
        if (now - scannedAt >= 3600e3 || new Date(scannedAt).toDateString() !== new Date(now).toDateString())
            scan();
        if (!notify)
            return;
        var sent = [];
        try { sent = JSON.parse(ledger.sent); } catch (err) { sent = []; }
        var due = EV.due(upcoming, sent, now);
        if (due.length === 0) {
            pump();                              // (in case a send never started)
            return;
        }
        for (var i = 0; i < due.length; i++)
            sent.push({ key: EV.eventKey(due[i].id), ms: due[i].ms });
        ledger.sent = JSON.stringify(sent.filter(x => x.ms > now - 10 * 86400e3));
        queue = queue.concat(due);
        pump();
    }

    // Location changed: everything is different. (Debounced: both
    // coordinates usually change together at startup.)
    onLatitudeChanged: relocate.restart()
    onLongitudeChanged: relocate.restart()
    Timer {
        id: relocate
        interval: 500
        onTriggered: { events.scannedAt = 0; events.check(); }
    }

    // First look a few seconds after startup (once the bar has set the
    // location), then every five minutes.
    Timer {
        running: true
        repeat: true
        interval: 5000
        onTriggered: { interval = 300000; events.check(); }
    }

    FileView {
        path: Quickshell.statePath("sky-events.json")
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: ledger
            property string sent: "[]"           // [{ key, ms }] announced, last 10 days
        }
    }

    // One notify-send at a time.
    property var queue: []
    function pump() {
        if (sender.running || queue.length === 0)
            return;
        var e = queue[0];
        queue = queue.slice(1);
        sender.command = ["notify-send", "-a", "deepfield sky", "-t", "20000", e.title, e.body];
        sender.running = true;
    }
    Process {
        id: sender
        onExited: Qt.callLater(events.pump)
    }

    IpcHandler {
        target: "sky"
        function list(): string {
            events.check();
            return events.ahead.map(e => Qt.formatDateTime(new Date(e.ms), "ddd d MMM  HH:mm").toLowerCase()
                                         + (e.notify ? "  *  " : "     ") + e.title).join("\n");
        }
        function preview(): void {
            events.check();
            var e = events.ahead.find(x => x.notify) || events.ahead[0];
            if (!e)
                return;
            events.queue = events.queue.concat([e]);
            events.pump();
        }
    }
}
