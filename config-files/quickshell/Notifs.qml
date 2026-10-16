pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The bar's notification daemon (org.freedesktop.Notifications on D-Bus).
// Only one daemon can own that name, so don't also run mako/dunst/fnott.
//
//   live         notifications on screen right now (Signals.qml draws them)
//   history      plain copies, newest first; they outlive the notifications
//   unread       received since you last opened the log
//   silence      radio silence: everything except critical goes straight to
//                the log without a popup. Survives restarts.
Singleton {
    id: notifs

    readonly property var live: server.trackedNotifications
    property var history: []
    readonly property int historyMax: 50
    readonly property int maxPopups: 3

    // The hints scripts use to say "replace my previous notification":
    //   notify-send -h string:x-dunst-stack-tag:music ...   (dunst/mako style)
    //   notify-send -h string:x-canonical-private-synchronous:music ...
    //   notify-send -h string:synchronous:music ...
    function stackTag(n) {
        var h = n.hints || {};
        return String(h["x-dunst-stack-tag"] || h["x-canonical-private-synchronous"]
                      || h["synchronous"] || h["private-synchronous"] || "");
    }
    // Unread = log entries newer than the last time you looked at the log.
    // Counted from the log itself, so a tagged notification that replaces its
    // previous entry (media keys, volume) is still one unread, not one more.
    property real seenAt: 0
    readonly property int unread: history.filter(h => h.time > seenAt).length
    property bool logOpen: false
    onLogOpenChanged: if (logOpen) seenAt = Date.now()

    readonly property bool silence: saved.silence
    function toggleSilence() { saved.silence = !saved.silence; }
    function clearHistory() { history = []; }
    function dismissAll() {
        for (const n of Array.from(server.trackedNotifications.values)) n.dismiss();
    }

    FileView {
        path: Quickshell.statePath("notifications.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: saved
            property bool silence: false
        }
    }

    NotificationServer {
        id: server
        keepOnReload: false                  // don't re-pop everything on every config edit
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false

        onNotification: n => {
            var critical = n.urgency === NotificationUrgency.Critical;
            var tag = notifs.stackTag(n);

            // A stack tag means "I replace my previous one": the old popup goes
            // away at once, and the log keeps only the newest entry for the tag.
            if (tag !== "") {
                for (const old of Array.from(server.trackedNotifications.values))
                    if (old !== n && notifs.stackTag(old) === tag) old.expire();
            }

            if (!n.transient) {
                var entry = {
                    app: n.appName,
                    summary: n.summary,
                    body: n.body,
                    time: Date.now(),
                    critical: critical,
                    tag: tag
                };
                var rest = tag === "" ? notifs.history : notifs.history.filter(h => h.tag !== tag);
                notifs.history = [entry].concat(rest).slice(0, notifs.historyMax);
                if (notifs.logOpen) notifs.seenAt = entry.time;   // arrived in front of you
            }

            // Untracked notifications are discarded: in radio silence they
            // only exist in the log.
            if (notifs.silence && !critical) return;
            n.tracked = true;

            // Never more than maxPopups on screen: the oldest non-critical goes.
            var shown = Array.from(server.trackedNotifications.values).filter(x => x.urgency !== NotificationUrgency.Critical);
            for (var i = 0; i < shown.length - notifs.maxPopups; i++) shown[i].expire();
        }
    }
}
