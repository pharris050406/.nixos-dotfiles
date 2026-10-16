import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The bar's own dmenu. Scripts don't talk to this directly: they pipe their
// list into scripts/dfmenu, which takes wmenu's flags and prints the choice.
//
// Under the hood it's a Unix socket at $XDG_RUNTIME_DIR/deepfield-picker.sock.
// A client sends   <prompt> TAB <"i" for case-insensitive> TAB <rows> 0x1D
//                  <items, one per line> 0x1D
// and gets back the chosen line, or nothing if it was cancelled.
// The panel appears once the list is in, already at its final size, so it
// opens in one frame. A list that takes longer than 150 ms opens it anyway,
// saying "receiving…". A new request replaces one that's still open (that one
// gets nothing back).
// Next to the socket, <socket>.pid holds the bar's pid: dfmenu checks that
// instead of test-connecting, which saves starting a process on every open.
PanelWindow {
    id: picker

    property Theme theme
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/deepfield-picker.sock"
    property Socket client: null

    visible: false
    anchors.top: true                       // top only: layer-shell centers it
    margins.top: 6
    exclusionMode: ExclusionMode.Normal     // just under the bar
    exclusiveZone: 0
    implicitWidth: Math.min(720, Math.round((screen ? screen.width : 1600) * 0.45))
    implicitHeight: view.implicitHeight
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "deepfield-picker"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    PickerView {
        id: view
        width: parent.width
        theme: picker.theme
        onAccepted: text => picker.finish(text)
        onCanceled: picker.finish(null)
    }

    function begin(sock, header) {
        if (client && client !== sock) finish(null);       // a newer request wins
        var f = header.split("\t");
        client = sock;
        view.reset(f[0] || "", (f[1] || "").indexOf("i") >= 0, parseInt(f[2]) || 0);
        showSoon.restart();
    }

    function receive(sock, data) {
        if (client !== sock) return;
        var items = data.split("\n");
        if (items.length && items[items.length - 1] === "") items.pop();
        view.setItems(items.filter(s => s !== ""));
        show();
    }

    function show() {
        showSoon.stop();
        visible = true;
        view.focusInput();
    }
    Timer { id: showSoon; interval: 150; onTriggered: picker.show() }

    function finish(text) {
        var c = client;
        client = null;
        showSoon.stop();
        visible = false;
        if (c) {
            if (text !== null) { c.write(text + "\n"); c.flush(); }
            c.connected = false;
        }
        // Finished connections stay allocated until the server restarts, so
        // restart it once in a while when nobody's using it.
        if (++served >= 64) Qt.callLater(recycle);
    }

    property int served: 0
    function recycle() {
        if (client) return;
        served = 0;
        server.active = false;
        server.active = true;
    }

    // Click anywhere else to cancel, like the Wi-Fi panel.
    PanelWindow {
        screen: picker.screen
        visible: picker.visible
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "deepfield-picker-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: picker.finish(null)
        }
    }

    // The bar's pid, for dfmenu's is-it-alive check. $PPID of this shell is
    // Quickshell itself.
    Process {
        running: true
        command: ["sh", "-c", "printf '%s\\n' \"$PPID\" > \"$1\"", "sh", picker.socketPath + ".pid"]
    }

    SocketServer {
        id: server
        active: true
        path: picker.socketPath
        handler: Socket {
            id: conn
            property int part: 0
            // The client went away (killed, Ctrl+C): drop its panel.
            onConnectedChanged: if (!connected && picker.client === conn) picker.finish(null)
            parser: SplitParser {
                splitMarker: "\x1d"
                onRead: data => {
                    if (conn.part === 0) picker.begin(conn, data);
                    else if (conn.part === 1) picker.receive(conn, data);
                    conn.part++;
                }
            }
        }
    }
}
