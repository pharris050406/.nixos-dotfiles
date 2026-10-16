import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Wi-Fi panel. Opens under the network widget (left click it).
//   ↑/↓ or j/k  move        Enter  connect        r  rescan
//   d / Delete  forget saved network               x  disconnect
//   e           sign in with username + password (enterprise / eduroam)
//   Esc         close (or cancel a login form); clicking anywhere outside also closes
// In a login form: Tab / Shift+Tab move between fields, Ctrl+H shows the password.
// Mouse works too: click a network to join, right click to forget it.
PanelWindow {
    id: panel

    property color accentColor: "#8caaee"
    property color textColor: "#cdd6f4"
    property color mutedColor: "#585b70"
    property color bgColor: "#181825"
    property color warnColor: "#e78284"
    property color barColor: "#181825"
    property string fontName: "JetBrainsMono Nerd Font"
    property int fontSize: 13
    property int rightMargin: 0

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/wifi.sh"
    readonly property color labelColor: Qt.rgba((textColor.r + mutedColor.r) / 2,
                                                (textColor.g + mutedColor.g) / 2,
                                                (textColor.b + mutedColor.b) / 2, 1)

    visible: false
    anchors { top: true; right: true }
    margins.right: rightMargin
    exclusionMode: ExclusionMode.Normal      // sit below the bar, don't reserve space
    exclusiveZone: 0
    implicitWidth: 400
    implicitHeight: frame.implicitHeight
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-wifi"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---------------- state ----------------
    property string wpaState: ""
    property string currentSsid: ""
    property string ip: ""
    property string iface: ""
    property string error: ""
    property var networks: []
    property bool scanning: false
    property int sel: 0
    property string pwFor: ""        // SSID whose login form is open
    property bool pwEap: false       // enterprise form (username/password/domain) vs plain password
    property bool showPw: false
    property string busy: ""
    property string message: ""
    property bool messageBad: false

    readonly property bool connected: wpaState === "COMPLETED"

    function open(rm) {
        rightMargin = rm;
        error = ""; message = ""; pwFor = "";
        visible = true;
        refresh();
        scan();
        keys.forceActiveFocus();
    }
    function close() { pwFor = ""; visible = false; }
    function toggle(rm) { if (visible) close(); else open(rm); }

    // ---------------- backend ----------------
    function parse(text) {
        var nets = [], sawNets = false;
        for (const line of text.split("\n")) {
            var f = line.split("|");
            if (f[0] === "ERR") {
                error = f.slice(1).join("|");
            } else if (f[0] === "STATE") {
                error = "";
                wpaState = f[1]; currentSsid = f[2]; ip = f[3]; iface = f[4];
            } else if (f[0] === "NET") {
                sawNets = true;
                nets.push({ dbm: Number(f[1]), sec: Number(f[2]),
                            savedId: Number(f[3]), ssid: f.slice(5).join("|") });
            } else if (f[0] === "OK" && f[1]) {
                message = "joined, " + f[1] + (f[2] ? "  (" + f[2] + ")" : "");
                messageBad = false;
            } else if (f[0] === "FORGOT") {
                var gone = forgetting;
                // Show it as unsaved now instead of waiting for the next scan.
                networks = networks.map(x => x.ssid === gone ? Object.assign({}, x, { savedId: -1 }) : x);
                message = "forgot " + gone + (Number(f[1]) > 1 ? " (" + f[1] + " saved copies)" : "")
                        + (f[2] ? ", " + f[2] : "");
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

    // Scripts run through `sh`, so a missing executable bit can't stall anything.
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
            panel.message = "scan timed out: try `wifi.sh scan` in a terminal";
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
    // Shared key handling for the form fields.
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
    // Forget asks twice (d d, or right-click twice) so a stray click can't wipe a login.
    property string confirmForget: ""
    property string forgetting: ""
    onSelChanged: if (confirmForget !== "") { confirmForget = ""; message = ""; }
    Timer { id: confirmTimer; interval: 3000; onTriggered: panel.confirmForget = "" }
    function forget(i) {
        var n = networks[i];
        if (!n || busy !== "") return;
        if (n.savedId < 0) {
            message = n.ssid + " isn't saved";
            messageBad = false;
            return;
        }
        if (confirmForget !== n.ssid) {
            confirmForget = n.ssid;
            message = "forget " + n.ssid + "? press d again";
            messageBad = true;
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
    component Field: Rectangle {
        id: fieldBox
        property alias text: input.text
        property string placeholder: ""
        property bool secret: false
        function focusInput() { input.forceActiveFocus(); }

        width: col.width
        height: panel.rowH + 4
        color: "transparent"
        border.width: 1
        border.color: input.activeFocus ? panel.accentColor : panel.mutedColor

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 6
            verticalAlignment: TextInput.AlignVCenter
            echoMode: fieldBox.secret && !panel.showPw ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            color: panel.textColor
            selectionColor: panel.accentColor
            selectedTextColor: panel.bgColor
            clip: true
            font { family: panel.fontName; pixelSize: panel.fontSize }
            Keys.onPressed: e => panel.formKey(e, fieldBox)
        }
        Text {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: fieldBox.placeholder
            color: panel.mutedColor
            font { family: panel.fontName; pixelSize: panel.fontSize }
        }
    }

    FontMetrics { id: fm; font.family: panel.fontName; font.pixelSize: panel.fontSize }
    readonly property int rowH: Math.ceil(fm.height) + 6

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

    Rectangle {
        id: frame
        width: parent.width
        implicitHeight: col.implicitHeight + 20
        color: Qt.rgba(panel.barColor.r, panel.barColor.g, panel.barColor.b, 1)
        border.width: 1
        border.color: panel.mutedColor

        Item {
            id: keys
            focus: true
            Keys.onPressed: e => {
                switch (e.key) {
                case Qt.Key_Escape: panel.close(); break;
                case Qt.Key_Down: case Qt.Key_J:
                    panel.sel = Math.min(panel.sel + 1, panel.networks.length - 1); break;
                case Qt.Key_Up: case Qt.Key_K:
                    panel.sel = Math.max(panel.sel - 1, 0); break;
                case Qt.Key_Return: case Qt.Key_Enter: panel.activate(panel.sel); break;
                case Qt.Key_R: panel.scan(); break;
                case Qt.Key_E: panel.activate(panel.sel, true); break;
                case Qt.Key_D: case Qt.Key_Delete: panel.forget(panel.sel); break;
                case Qt.Key_X: panel.act(["disconnect"], "disconnecting"); break;
                default: return;
                }
                e.accepted = true;
            }
        }

        Column {
            id: col
            x: 10; y: 10
            width: parent.width - 20
            spacing: 6

            // header: what we're connected to right now
            Item {
                width: col.width
                height: panel.rowH
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "wifi " + (panel.iface || "")
                    color: panel.labelColor
                    font { family: panel.fontName; pixelSize: panel.fontSize }
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.error ? "unavailable"
                        : panel.connected ? panel.currentSsid + "  " + (panel.ip || "no address")
                        : (panel.wpaState || "…").toLowerCase()
                    color: panel.error ? panel.warnColor : panel.textColor
                    font { family: panel.fontName; pixelSize: panel.fontSize }
                }
            }

            // setup help when nmcli can't reach NetworkManager
            Text {
                visible: panel.error.indexOf("NetworkManager") >= 0
                width: col.width
                wrapMode: Text.Wrap
                color: panel.textColor
                font { family: panel.fontName; pixelSize: panel.fontSize - 1 }
                text: panel.error + "\n\n" +
                      "In your NixOS config:\n" +
                      "  networking.networkmanager.enable = true;\n" +
                      "  users.users." + (Quickshell.env("USER") || "you") + ".extraGroups = [ \"networkmanager\" ];\n" +
                      "then rebuild, and log out and back in so the group applies."
            }

            // network list
            ListView {
                id: list
                visible: panel.error === ""
                width: col.width
                height: Math.max(1, Math.min(count, 10)) * panel.rowH
                clip: true
                model: panel.networks
                currentIndex: panel.sel
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === panel.sel
                    readonly property bool isCurrent: panel.connected && modelData.ssid === panel.currentSsid
                    readonly property color ink: selected ? panel.bgColor : panel.textColor
                    readonly property int lvl: panel.bars(modelData.dbm)

                    width: list.width
                    height: panel.rowH
                    color: selected ? panel.accentColor : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            text: "▂▄▆█".slice(0, row.lvl)
                            color: row.ink
                            font { family: panel.fontName; pixelSize: panel.fontSize }
                        }
                        Text {
                            text: "▂▄▆█".slice(row.lvl) + "  "
                            color: row.selected ? Qt.rgba(panel.bgColor.r, panel.bgColor.g, panel.bgColor.b, 0.35)
                                                : panel.mutedColor
                            font { family: panel.fontName; pixelSize: panel.fontSize }
                        }
                        Text {
                            width: list.width - 6 - 8 * fm.averageCharacterWidth - tag.implicitWidth - 12
                            elide: Text.ElideRight
                            text: (row.modelData.sec > 0 ? "\uf023 " : "  ") + row.modelData.ssid
                            color: row.ink
                            font { family: panel.fontName; pixelSize: panel.fontSize; bold: row.isCurrent }
                        }
                    }
                    Text {
                        id: tag
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.isCurrent ? "connected" : row.modelData.savedId >= 0 ? "saved"
                            : row.modelData.sec === 2 ? "login" : ""
                        color: row.selected ? panel.bgColor : row.isCurrent ? panel.accentColor : panel.labelColor
                        font { family: panel.fontName; pixelSize: panel.fontSize }
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
                visible: panel.error === "" && panel.networks.length === 0
                text: panel.scanning ? "scanning…" : "no networks found, press r to rescan"
                color: panel.labelColor
                font { family: panel.fontName; pixelSize: panel.fontSize }
            }

            // login form: one field for passwords, three for enterprise (eduroam etc)
            Column {
                visible: panel.pwFor !== ""
                width: col.width
                spacing: 4

                Text {
                    text: (panel.pwEap ? "sign in to " : "password for ") + panel.pwFor
                    color: panel.labelColor
                    font { family: panel.fontName; pixelSize: panel.fontSize }
                }
                Field { id: idField; visible: panel.pwEap; placeholder: "username (e.g. you@school.edu)" }
                Field { id: pwField; secret: true; placeholder: "password" }
                Field { id: domField; visible: panel.pwEap; placeholder: "server domain (default: part after @)" }
                Text {
                    visible: panel.pwEap && domField.text.trim() === "" && idField.text.indexOf("@") < 0
                    width: col.width
                    wrapMode: Text.Wrap
                    text: "without a server domain, a fake network with this name could capture your password"
                    color: panel.warnColor
                    font { family: panel.fontName; pixelSize: panel.fontSize - 1 }
                }
            }

            // status + hints
            Text {
                width: col.width
                wrapMode: Text.Wrap
                text: panel.busy ? panel.busy + "…"
                    : panel.message ? panel.message
                    : panel.pwFor ? "enter join   tab next field   ctrl+h show password   esc cancel"
                    : (panel.scanning ? "scanning…   " : "") + "enter join   e login   r rescan   d forget   x disconnect   esc"
                color: panel.message && panel.messageBad ? panel.warnColor
                     : panel.busy ? panel.accentColor : panel.labelColor
                font { family: panel.fontName; pixelSize: panel.fontSize - 1 }
            }
        }
    }
}
