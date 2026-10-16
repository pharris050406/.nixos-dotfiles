pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Lib.js" as Lib

// Network state. Same two scripts as before, same output protocols:
//   net-status.sh  ->  ip|down|up
//   net-info.sh    ->  iface|gw|ssid|rx|tx|ping
Singleton {
    id: net

    readonly property int samples: 60

    property string address: "0.0.0.0"
    property real down: 0                   // bytes/s
    property real up: 0
    property real downPeak: 0
    property real upPeak: 0
    property var downHistory: Lib.zeros(samples)
    property var upHistory: Lib.zeros(samples)
    readonly property real activity: Lib.rateLevel(down + up)

    property bool gotInfo: false
    property string iface: ""
    property string gateway: ""
    property string ssid: ""
    property real rxTotal: 0
    property real txTotal: 0
    property real pingMs: -1
    property var pingHistory: Lib.zeros(samples)
    property int _missed: 0

    readonly property bool offline: gotInfo && iface === ""
    // Route is up but the internet isn't answering (3 failed pings in a row).
    readonly property bool unreachable: gotInfo && iface !== "" && _missed >= 3

    Process {
        command: ["sh", "-c", "exec \"$HOME/.config/quickshell/scripts/net-status.sh\""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim().split("|");
                if (p.length !== 3) return;
                net.address = p[0];
                net.down = Lib.parseRate(p[1]);
                net.up = Lib.parseRate(p[2]);
                net.downPeak = Math.max(net.downPeak, net.down);
                net.upPeak = Math.max(net.upPeak, net.up);
                net.downHistory = Lib.push(net.downHistory, Lib.rateLevel(net.down), net.samples);
                net.upHistory = Lib.push(net.upHistory, Lib.rateLevel(net.up), net.samples);
            }
        }
    }

    Process {
        command: ["sh", "-c", "exec \"$HOME/.config/quickshell/scripts/net-info.sh\""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim().split("|");
                if (p.length < 6) return;
                net.iface = p[0];
                net.gateway = p[1];
                net.ssid = p[2];
                net.rxTotal = Number(p[3]) || 0;
                net.txTotal = Number(p[4]) || 0;
                net.pingMs = p[5] === "" ? -1 : Number(p[5]);
                net._missed = net.iface !== "" && net.pingMs < 0 ? net._missed + 1 : 0;
                if (net.iface !== "")
                    net.pingHistory = Lib.push(net.pingHistory, Lib.latencyLevel(net.pingMs), net.samples);
                net.gotInfo = true;
            }
        }
    }

    // ---- copy address (needs wl-clipboard) ----
    signal copied(bool ok)
    Process {
        id: copyProc
        onExited: (code, status) => net.copied(code === 0)
    }
    function copyAddress() {
        copyProc.command = ["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", net.address];
        copyProc.running = true;
    }
}
