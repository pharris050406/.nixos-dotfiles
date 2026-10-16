pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Lib.js" as Lib

// CPU, memory, battery, uptime. Linux: read straight from /proc and /sys with
// FileView on a timer, so polling costs no processes at all.
// Views never poll; they only read this.
Singleton {
    id: sys

    readonly property int samples: 60

    // ---------------- cpu ----------------
    property int cpu: 0
    property real cpuSmooth: 0                 // 0..1, eased
    property var cpuHistory: Lib.zeros(samples)
    property real _idle: 0
    property real _total: 0
    property int _hotRun: 0
    // "Hot" only after 3 straight seconds over 85%, and it stays hot until
    // load falls under 70%. A compile spike shouldn't make the bar flicker.
    property bool cpuHot: false

    // /proc/stat, first line:
    //   cpu  user nice system idle iowait irq softirq steal guest guest_nice
    // guest/guest_nice are already counted in user/nice, so they're left out.
    // Idle includes iowait (waiting on disk isn't work).
    // The same file has "btime <epoch>", which is where uptime comes from.
    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: {
            var txt = statFile.text();
            var m = /^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/.exec(txt);
            if (m) {
                var total = 0;
                for (var i = 1; i <= 8; i++) total += Number(m[i]);
                var idle = Number(m[4]) + Number(m[5]);
                if (sys._total > 0 && total > sys._total) {
                    sys.cpu = Math.round(100 * (1 - (idle - sys._idle) / (total - sys._total)));
                    sys.cpuHistory = Lib.push(sys.cpuHistory, sys.cpu / 100, sys.samples);
                    // Stars don't change temperature instantly: ~3 s time constant.
                    sys.cpuSmooth += (sys.cpu / 100 - sys.cpuSmooth) * 0.3;
                    sys._hotRun = sys.cpu > 85 ? sys._hotRun + 1 : 0;
                    if (sys._hotRun >= 3) sys.cpuHot = true;
                    else if (sys.cpu < 70) sys.cpuHot = false;
                }
                sys._total = total;
                sys._idle = idle;
            }
            if (sys.bootSec <= 0) {
                var b = /^btime\s+(\d+)/m.exec(txt);
                if (b) sys.bootSec = Number(b[1]);
            }
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: statFile.reload()
    }

    // ---------------- memory ----------------
    // used = MemTotal - MemAvailable (the kernel's own estimate of what could be
    // handed out without swapping, so page cache doesn't count as used).
    property int mem: 0
    property real memUsed: 0
    property real memTotal: 0
    property var memHistory: Lib.zeros(samples)
    property bool memHot: false

    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            var txt = memFile.text();
            var kb = key => { var m = new RegExp("^" + key + ":\\s+(\\d+)", "m").exec(txt); return m ? Number(m[1]) * 1024 : -1; };
            var total = kb("MemTotal");
            var avail = kb("MemAvailable");
            if (total <= 0) return;
            if (avail < 0)                       // pre-3.14 kernels: no MemAvailable
                avail = Math.max(0, kb("MemFree")) + Math.max(0, kb("Buffers")) + Math.max(0, kb("Cached"));
            var used = Math.max(0, total - avail);
            sys.memUsed = used;
            sys.memTotal = total;
            sys.mem = Math.round(100 * used / total);
            sys.memHistory = Lib.push(sys.memHistory, used / total, sys.samples);
            if (sys.mem >= 88) sys.memHot = true;
            else if (sys.mem < 82) sys.memHot = false;
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: memFile.reload()
    }

    // ---------------- battery ----------------
    // batteryFlags keeps the old bitmask: 1 discharging, 2 charging, 4 critical.
    // The battery is found once at startup (the first power_supply of type
    // Battery that isn't a mouse or headset); a desktop has none, and then
    // nothing is polled.
    property bool hasBattery: false
    property bool batteryKnown: false
    property int battery: 0
    property int batteryFlags: 0
    property int batteryMinutes: -1
    readonly property bool discharging: (batteryFlags & 1) !== 0
    readonly property bool charging: (batteryFlags & 2) !== 0
    readonly property string batteryState: charging ? "charging" : discharging ? "on battery" : "full"
    readonly property bool batteryLow: hasBattery && discharging && battery <= 20
    readonly property bool batteryCritical: hasBattery && discharging && battery <= 10

    property string batteryDir: ""

    Process {
        running: true
        command: ["sh", "-c",
            "for d in /sys/class/power_supply/*; do " +
            "  t=; s=; read -r t 2>/dev/null < \"$d/type\"; read -r s 2>/dev/null < \"$d/scope\"; " +
            "  [ \"$t\" = Battery ] && [ \"$s\" != Device ] && { echo \"$d\"; exit 0; }; " +
            "done; echo none"]
        stdout: SplitParser {
            onRead: data => {
                var d = data.trim();
                sys.batteryDir = d === "none" ? "" : d;
                if (d === "none") sys.hasBattery = false;
            }
        }
    }

    // uevent has every field in one read:
    //   POWER_SUPPLY_STATUS=Discharging   POWER_SUPPLY_CAPACITY=83
    //   POWER_SUPPLY_ENERGY_NOW / POWER_NOW  (µWh, µW)   or
    //   POWER_SUPPLY_CHARGE_NOW / CURRENT_NOW (µAh, µA), depending on the firmware
    FileView {
        id: batFile
        path: sys.batteryDir !== "" ? sys.batteryDir + "/uevent" : ""
        printErrors: false
        onLoaded: {
            var v = {};
            for (const line of batFile.text().split("\n")) {
                var i = line.indexOf("=");
                if (i > 0) v[line.slice(0, i).replace("POWER_SUPPLY_", "")] = line.slice(i + 1).trim();
            }
            if (v.PRESENT === "0") { sys.hasBattery = false; return; }
            var num = k => v[k] === undefined || v[k] === "" ? NaN : Math.abs(Number(v[k]));

            var cap = num("CAPACITY");
            if (isNaN(cap)) {
                var frac = num("ENERGY_NOW") / num("ENERGY_FULL");
                if (isNaN(frac)) frac = num("CHARGE_NOW") / num("CHARGE_FULL");
                cap = isNaN(frac) ? 0 : 100 * frac;
            }

            var st = v.STATUS || "";
            var flags = st === "Discharging" ? 1 : st === "Charging" ? 2 : 0;
            if (v.CAPACITY_LEVEL === "Critical") flags |= 4;

            // Time left: what's in the tank over the rate it's draining.
            var mins = -1;
            if (flags & 1) {
                var h = num("ENERGY_NOW") / num("POWER_NOW");
                if (!isFinite(h)) h = num("CHARGE_NOW") / num("CURRENT_NOW");
                if (isFinite(h) && h > 0) mins = Math.round(h * 60);
            }

            sys.hasBattery = true;
            sys.battery = Math.max(0, Math.min(100, Math.round(cap)));
            sys.batteryFlags = flags;
            sys.batteryMinutes = mins;
            sys.batteryKnown = true;
        }
    }
    Timer {
        interval: 5000; repeat: true
        running: sys.batteryDir !== ""
        onTriggered: batFile.reload()
    }

    // ---------------- uptime ----------------
    // Boot time comes from the btime line of /proc/stat (read above).
    property real bootSec: 0
    function uptime() { return bootSec > 0 ? Date.now() / 1000 - bootSec : 0 }
}
