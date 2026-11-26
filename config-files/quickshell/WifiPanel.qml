import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Lib.js" as Lib

// The comms panel: left-click the network widget. Same instrument look as the
// hover cards and the picker. Shows the wired link if there is one, and the
// Wi-Fi networks if there's a Wi-Fi adapter.
// Keys (? in the panel shows them): ↑↓/jk move · enter join · e enterprise login
//   r rescan · d forget (twice) · x disconnect · esc close
// Mouse: click joins, right-click (twice) forgets, clicking outside closes.
PanelWindow {
    id: panel

    property Theme theme
    property int rightMargin: 0

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/wifi.sh"
    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)
    readonly property color edge: Lib.mix(theme.muted, theme.barColor, 0.35)
    readonly property int pad: 14

    // Wired: the default route goes through something that isn't the Wi-Fi adapter.
    readonly property bool wired: Net.iface !== "" && Net.iface !== wifiIface
    readonly property bool hasWifi: error === ""

    visible: false
    anchors { top: true; right: true }
    margins.right: rightMargin
    exclusionMode: ExclusionMode.Normal      // sit below the bar, don't reserve space
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: frame.height
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-wifi"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---------------- state ----------------
    property string wpaState: ""
    property string currentSsid: ""
    property string ip: ""
    property string wifiIface: ""
    property string error: ""
    property var networks: []
    property bool scanning: false
    property int sel: 0
    property string pwFor: ""        // SSID whose login form is open
    property bool pwEap: false       // enterprise form (username/password/domain) vs plain password
    property bool showPw: false
    property bool help: false
    property string busy: ""
    property string message: ""
    property bool messageBad: false

    readonly property bool connected: wpaState === "COMPLETED"

    function open(rm) {
        rightMargin = rm;
        error = ""; message = ""; pwFor = ""; help = false;
        visible = true;
        refresh();
        scan();
        keys.forceActiveFocus();
        drop.restart();
    }
    function close() { pwFor = ""; visible = false; }
    function toggle(rm) { if (visible) close(); else open(rm); }

    // Messages fade out on their own; errors stay until the next action.
    Timer { id: messageTimer; interval: 4000; onTriggered: if (!panel.messageBad) panel.message = "" }
    onMessageChanged: if (message !== "") messageTimer.restart()

    // ---------------- backend (scripts/wifi.sh) ----------------
    function parse(text) {
        var nets = [], sawNets = false;
        for (const line of text.split("\n")) {
            var f = line.split("|");
            if (f[0] === "ERR") {
                error = f.slice(1).join("|");
            } else if (f[0] === "STATE") {
                error = "";
                wpaState = f[1]; currentSsid = f[2]; ip = f[3]; wifiIface = f[4];
            } else if (f[0] === "NET") {
                sawNets = true;
                nets.push({ dbm: Number(f[1]), sec: Number(f[2]),
                            savedId: Number(f[3]), ssid: f.slice(5).join("|") });
            } else if (f[0] === "OK" && f[1]) {
                message = "joined";
                messageBad = false;
            } else if (f[0] === "FORGOT") {
                var gone = forgetting;
                // Show it as unsaved now instead of waiting for the next scan.
                networks = networks.map(x => x.ssid === gone ? Object.assign({}, x, { savedId: -1 }) : x);
                message = f[2] ? f[2] : "forgot " + gone;
                messageBad = f[2] !== "";
                forgetting = "";
            } else if (f[0] === "FAIL") {
                message = f.slice(1).join("|");
                messageBad = true;
            }
        }
        if (sawNets) {
            nets.sort((a, b) => (b.ssid === currentSsid) - (a.ssid === currentSsid) || b.dbm - a.dbm);
            networks = nets;
            sel = Math.max(0, Math.min(sel, nets.length - 1));
        }
    }

    Process {
        id: statusProc
        command: ["sh", panel.script, "status"]
        stdout: StdioCollector { onStreamFinished: panel.parse(this.text) }
    }
    function refresh() { if (!statusProc.running) statusProc.running = true; }
    Timer { interval: 2000; repeat: true; running: panel.visible; onTriggered: panel.refresh() }

    Process {
        id: scanProc
        command: ["sh", panel.script, "scan"]
        stdout: StdioCollector {
            onStreamFinished: { panel.scanning = false; panel.parse(this.text); }
        }
        stderr: StdioCollector { id: scanErr }
        onExited: (code, status) => {
            panel.scanning = false;
            if (code !== 0 && panel.networks.length === 0) {
                panel.message = "scan failed: " + (scanErr.text.trim().split("\n")[0] || "exit " + code);
                panel.messageBad = true;
            }
        }
    }
    function scan() {
        if (scanProc.running) return;
        scanning = true;
        scanProc.running = true;
        scanWatchdog.restart();
    }
    Timer {
        id: scanWatchdog
        interval: 20000
        onTriggered: if (scanProc.running) {
            scanProc.running = false;
            panel.scanning = false;
            panel.message = "scan timed out";
            panel.messageBad = true;
        }
    }

    // Secrets go to the script on stdin, never in its arguments (`ps` shows
    // arguments to every user on the system).
    property string pendingSecret: ""
    Process {
        id: actProc
        onStarted: {
            if (stdinEnabled) {
                write(panel.pendingSecret + "\n");
                stdinEnabled = false;          // closes stdin -> script's read returns
            }
            panel.pendingSecret = "";
        }
        onExited: { panel.busy = ""; panel.pendingSecret = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                panel.busy = "";
                panel.parse(this.text);
                panel.refresh();
                panel.scan();
            }
        }
    }
    function act(args, busyText, secret) {
        if (actProc.running) return;
        busy = busyText;
        message = "";
        pendingSecret = secret !== undefined ? secret : "";
        actProc.stdinEnabled = secret !== undefined;
        actProc.command = ["sh", script].concat(args);   // argv, never a shell string
        actProc.running = true;
    }

    // ---------------- actions ----------------
    // forceEap: open the username/password form even if the scan didn't flag it.
    function activate(i, forceEap) {
        var n = networks[i];
        if (!n || busy !== "") return;
        if (!forceEap && connected && n.ssid === currentSsid) return;
        if (forceEap || (n.sec > 0 && n.savedId < 0)) {
            pwFor = n.ssid;
            pwEap = forceEap || n.sec === 2;
            showPw = false;
            idField.text = ""; pwField.text = ""; domField.text = "";
            (pwEap ? idField : pwField).focusInput();
            return;
        }
        act(["connect", n.ssid], "joining " + n.ssid);
    }
    function cancelForm() {
        pwFor = "";
        idField.text = ""; pwField.text = ""; domField.text = "";
        keys.forceActiveFocus();
    }
    function submitForm() {
        var s = pwFor;
        var secret = pwField.text;
        var args = pwEap ? ["connect-eap", s, idField.text.trim(), domField.text.trim()]
                         : ["connect", s, "-"];
        cancelForm();
        act(args, pwEap ? "signing in to " + s : "joining " + s, secret);
    }
    // Form fields: enter submits, esc cancels, tab cycles, ctrl+h shows the password.
    function formKey(e, field) {
        var order = pwEap ? [idField, pwField, domField] : [pwField];
        var at = order.indexOf(field);
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) submitForm();
        else if (e.key === Qt.Key_Escape) cancelForm();
        else if (e.key === Qt.Key_Backtab || (e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier)))
            order[(at + order.length - 1) % order.length].focusInput();
        else if (e.key === Qt.Key_Tab) order[(at + 1) % order.length].focusInput();
        else if (e.key === Qt.Key_H && (e.modifiers & Qt.ControlModifier)) showPw = !showPw;
        else return;
        e.accepted = true;
    }
    // Forget asks twice so a stray key or click can't wipe a saved login.
    property string confirmForget: ""
    property string forgetting: ""
    onSelChanged: confirmForget = ""
    Timer { id: confirmTimer; interval: 3000; onTriggered: panel.confirmForget = "" }
    function forget(i) {
        var n = networks[i];
        if (!n || busy !== "" || n.savedId < 0) return;
        if (confirmForget !== n.ssid) {
            confirmForget = n.ssid;              // the row's tag turns into "forget?"
            confirmTimer.restart();
            return;
        }
        confirmForget = "";
        confirmTimer.stop();
        forgetting = n.ssid;
        act(["forget", n.ssid], "forgetting " + n.ssid);
    }

    function bars(dbm) {     // dBm -> 0..4 (handles drivers that report 0-100 too)
        if (dbm > 0) return Math.min(4, Math.round(dbm / 25));
        return dbm >= -55 ? 4 : dbm >= -65 ? 3 : dbm >= -75 ? 2 : dbm >= -85 ? 1 : 0;
    }

    // ---------------- view ----------------
    FontMetrics { id: fm; font.family: panel.theme.fontFamily; font.pixelSize: panel.theme.fontSize }
    readonly property int rowH: Math.ceil(fm.height) + 8

    // One line of the login form, styled like the picker's input.
    component Field: Item {
        id: fieldBox
        property alias text: input.text
        property string placeholder: ""
        property bool secret: false
        function focusInput() { input.forceActiveFocus(); }

        width: body.width
        height: panel.rowH
        Text {
            id: caret
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: input.activeFocus ? panel.theme.accent3 : panel.theme.muted
            font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize + 2; bold: true }
        }
        TextInput {
            id: input
            anchors { left: caret.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
            echoMode: fieldBox.secret && !panel.showPw ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            color: panel.theme.foreground
            selectionColor: panel.theme.accent3
            selectedTextColor: panel.theme.barColor
            cursorVisible: activeFocus
            clip: true
            font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize }
            Keys.onPressed: e => panel.formKey(e, fieldBox)
        }
        Text {
            anchors { left: input.left; verticalCenter: parent.verticalCenter }
            visible: input.text === ""
            text: fieldBox.placeholder
            color: panel.theme.muted
            font: input.font
        }
    }

    // Click-off-to-close: an invisible full-screen layer behind the panel
    // (panel is on Overlay, this on Top) that closes it on any click.
    PanelWindow {
        screen: panel.screen
        visible: panel.visible
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-wifi-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: panel.close()
        }
    }

    ParallelAnimation {      // same drop-in as the hover cards
        id: drop
        NumberAnimation { target: frame; property: "opacity"; from: 0; to: 1; duration: 140 }
        NumberAnimation { target: frame; property: "y"; from: -4; to: 0; duration: 180; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: frame
        width: parent.width
        height: body.implicitHeight + 2 * panel.pad + 2
        color: Qt.rgba(panel.theme.barColor.r, panel.theme.barColor.g, panel.theme.barColor.b, 1)
        border.width: 1
        border.color: panel.edge

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2
            color: panel.wired || panel.connected ? panel.theme.accent3 : panel.theme.accent6
        }

        Item {
            id: keys
            focus: true
            Keys.onPressed: e => {
                switch (e.key) {
                case Qt.Key_Escape: if (panel.help) panel.help = false; else panel.close(); break;
                case Qt.Key_Down: case Qt.Key_J:
                    panel.sel = Math.min(panel.sel + 1, panel.networks.length - 1); break;
                case Qt.Key_Up: case Qt.Key_K:
                    panel.sel = Math.max(panel.sel - 1, 0); break;
                case Qt.Key_Return: case Qt.Key_Enter: panel.activate(panel.sel); break;
                case Qt.Key_R: if (panel.hasWifi) panel.scan(); break;
                case Qt.Key_E: panel.activate(panel.sel, true); break;
                case Qt.Key_D: case Qt.Key_Delete: panel.forget(panel.sel); break;
                case Qt.Key_X: if (panel.connected) panel.act(["disconnect"], "disconnecting"); break;
                case Qt.Key_Question: panel.help = !panel.help; break;
                default: return;
                }
                e.accepted = true;
            }
        }

        Column {
            id: body
            x: panel.pad
            y: panel.pad + 2
            width: parent.width - 2 * panel.pad
            spacing: 8

            // heading: COMMS ......................... scanning… / joining x…
            Item {
                width: parent.width
                height: headText.implicitHeight
                Text {
                    id: headText
                    text: "COMMS"
                    color: panel.wired || panel.connected ? panel.theme.accent3 : panel.theme.accent6
                    font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize - 3; letterSpacing: 2.5; bold: true }
                }
                Text {
                    anchors { right: parent.right; baseline: headText.baseline }
                    text: panel.busy ? panel.busy + "…" : panel.scanning ? "scanning…" : ""
                    color: panel.label
                    font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize - 2 }
                }
            }

            // the links, as instrument readouts
            Column {
                spacing: 4
                Readout {
                    visible: panel.wired
                    theme: panel.theme
                    k: "wired"
                    v: Net.iface + "  " + Net.address
                }
                Readout {
                    theme: panel.theme
                    k: "wi-fi"
                    v: !panel.hasWifi ? panel.error.replace(/\s*[(:].*$/, "")
                     : panel.connected ? panel.currentSsid + "  " + (panel.ip || "no address")
                     : "not connected"
                    dim: !panel.connected
                }
            }

            Rectangle { visible: panel.hasWifi; width: parent.width; height: 1; color: panel.edge }

            // networks: same rows as the picker
            ListView {
                id: list
                visible: panel.hasWifi && count > 0
                width: parent.width
                height: Math.min(count, 10) * panel.rowH
                clip: true
                model: panel.networks
                currentIndex: panel.sel
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === panel.sel
                    readonly property bool isCurrent: panel.connected && modelData.ssid === panel.currentSsid
                    readonly property bool confirming: modelData.ssid === panel.confirmForget
                    readonly property int lvl: panel.bars(modelData.dbm)
                    readonly property color ink: isCurrent ? panel.theme.accent3
                                               : selected ? panel.theme.foreground
                                               : Lib.mix(panel.theme.foreground, panel.theme.muted, 0.25)
                    width: list.width
                    height: panel.rowH

                    Rectangle {
                        anchors.fill: parent
                        visible: row.selected
                        color: Qt.rgba(panel.theme.accent3.r, panel.theme.accent3.g, panel.theme.accent3.b, 0.14)
                        Rectangle { width: 2; height: parent.height; color: panel.theme.accent3 }
                    }
                    Text {             // signal: lit bars, then the rest in muted
                        id: sig
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        textFormat: Text.StyledText
                        text: "▂▄▆█".slice(0, row.lvl) + "<font color='" + panel.theme.muted + "'>" + "▂▄▆█".slice(row.lvl) + "</font>"
                        color: row.ink
                        font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize }
                    }
                    Text {
                        anchors { left: sig.right; leftMargin: 10; right: tag.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: row.modelData.ssid
                        elide: Text.ElideRight
                        color: row.ink
                        font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize; bold: row.selected || row.isCurrent }
                    }
                    Text {
                        id: tag
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        text: row.confirming ? "forget?"
                            : row.modelData.savedId >= 0 ? "saved"
                            : row.modelData.sec === 2 ? "login"
                            : row.modelData.sec > 0 ? "" : ""
                        color: row.confirming ? panel.theme.accent6 : panel.label
                        font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize - 2 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: panel.sel = row.index
                        onClicked: m => {
                            if (m.button === Qt.RightButton) panel.forget(row.index);
                            else panel.activate(row.index);
                        }
                    }
                }
            }

            Text {
                visible: panel.hasWifi && panel.networks.length === 0 && !panel.scanning
                text: "no networks"
                color: panel.theme.muted
                font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize }
            }

            // login form: one field for a password, three for enterprise (eduroam etc)
            Column {
                visible: panel.pwFor !== ""
                width: parent.width
                spacing: 2

                Rectangle { width: parent.width; height: 1; color: panel.edge }
                Text {
                    topPadding: 6
                    text: (panel.pwEap ? "sign in · " : "password · ") + panel.pwFor
                    color: panel.label
                    font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize - 2 }
                }
                Field { id: idField; visible: panel.pwEap; placeholder: "username" }
                Field { id: pwField; secret: true; placeholder: "password" }
                Field { id: domField; visible: panel.pwEap; placeholder: "server domain (optional)" }
                // Kept on purpose: without a domain to check the certificate
                // against, a fake hotspot with the same name can take the password.
                Text {
                    visible: panel.pwEap && domField.text.trim() === "" && idField.text.indexOf("@") < 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "no domain: the server's certificate can't be checked"
                    color: panel.theme.accent6
                    font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize - 3 }
                }
            }

            // messages (errors stay, the rest clear themselves), or ? help
            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: panel.help
                    ? (panel.pwFor ? "enter join   tab next   ctrl+h show   esc cancel"
                                   : "enter join   e login   r rescan   d forget   x disconnect   esc")
                    : panel.message
                color: panel.messageBad && !panel.help ? panel.theme.accent6 : panel.theme.muted
                font { family: panel.theme.fontFamily; pixelSize: panel.theme.fontSize - 3 }
            }
        }
    }
}
