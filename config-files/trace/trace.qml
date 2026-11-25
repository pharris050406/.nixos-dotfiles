// ~/.config/trace/trace.qml — click-through tracing overlay with a mouse-driven edit mode
// Launched by the `trace` script; image path comes from $TRACE_IMG.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property string img: Quickshell.env("TRACE_IMG") ?? ""
    property real alpha: 0.4
    property bool editing: false
    property bool shown: true
    property bool flipH: false
    property bool flipV: false
    property real rot: 0

    PanelWindow {
        id: win
        visible: root.shown
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "trace"
        WlrLayershell.keyboardFocus: root.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // empty region = clicks pass through; null = whole screen takes input (edit mode)
        property Region clickThrough: Region {}
        mask: root.editing ? null : clickThrough

        Item {
            id: canvas
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.editing = false
            Keys.onPressed: function (e) {
                if (e.key === Qt.Key_H) { root.flipH = !root.flipH; e.accepted = true }
                else if (e.key === Qt.Key_V) { root.flipV = !root.flipV; e.accepted = true }
                else if (e.key === Qt.Key_R) {
                    root.rot = (root.rot + ((e.modifiers & Qt.ShiftModifier) ? -90 : 90) + 360) % 360
                    e.accepted = true
                }
                else if (e.key === Qt.Key_0) { root.rot = 0; e.accepted = true }
            }
            onWidthChanged: frame.fit()
            onHeightChanged: frame.fit()

            // screen dim while editing
            Rectangle {
                anchors.fill: parent
                visible: root.editing
                color: "#33000000"
            }

            // right-click anywhere = done
            MouseArea {
                anchors.fill: parent
                enabled: root.editing
                acceptedButtons: Qt.RightButton
                onClicked: root.editing = false
            }

            Item {
                id: frame
                rotation: root.rot                   // rotates around the center
                readonly property real aspect: pic.sourceSize.height > 0
                    ? pic.sourceSize.width / pic.sourceSize.height : 1

                function fit() {
                    if (pic.sourceSize.width <= 0 || canvas.width <= 0 || canvas.height <= 0) return
                    const s = Math.min(1, canvas.width * 0.7 / pic.sourceSize.width,
                                          canvas.height * 0.7 / pic.sourceSize.height)
                    width = pic.sourceSize.width * s
                    height = width / aspect
                    x = (canvas.width - width) / 2
                    y = (canvas.height - height) / 2
                }

                function scaleBy(f) {
                    const cx = x + width / 2, cy = y + height / 2
                    width = Math.max(40, width * f)
                    height = width / aspect
                    x = cx - width / 2
                    y = cy - height / 2
                }

                Image {
                    id: pic
                    anchors.fill: parent
                    fillMode: Image.Stretch          // frame already keeps the aspect ratio
                    source: root.img === "" ? "" : "file://" + root.img
                    opacity: root.alpha
                    smooth: true
                    mipmap: true
                    onSourceSizeChanged: frame.fit()
                    transform: Scale {
                        origin.x: pic.width / 2
                        origin.y: pic.height / 2
                        xScale: root.flipH ? -1 : 1
                        yScale: root.flipV ? -1 : 1
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.editing
                    color: "transparent"
                    border.color: "#3b82f6"
                    border.width: 2
                }

                // drag = move, wheel = opacity, ctrl+wheel = size, double-click = done
                MouseArea {
                    anchors.fill: parent
                    enabled: root.editing
                    acceptedButtons: Qt.LeftButton
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: frame
                    onDoubleClicked: root.editing = false
                    onWheel: function (w) {
                        // Qt can turn alt+wheel into horizontal scroll, so check both axes
                        const dy = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x
                        const up = dy > 0
                        if (w.modifiers & Qt.AltModifier)
                            root.rot = (root.rot + (up ? 1 : -1) + 360) % 360
                        else if (w.modifiers & Qt.ControlModifier)
                            frame.scaleBy(up ? 1.05 : 1 / 1.05)
                        else
                            root.alpha = Math.max(0.05, Math.min(1, root.alpha + (up ? 0.05 : -0.05)))
                    }
                }

                // bottom-right corner = resize (keeps aspect ratio)
                Rectangle {
                    width: 18; height: 18
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -9
                    visible: root.editing
                    radius: 9
                    color: "#3b82f6"
                    border.color: "white"
                    border.width: 2

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.SizeFDiagCursor
                        property real startW
                        property point startP
                        onPressed: function (m) {
                            startW = frame.width
                            startP = mapToItem(canvas, m.x, m.y)
                        }
                        onPositionChanged: function (m) {
                            if (!pressed) return
                            const p = mapToItem(canvas, m.x, m.y)
                            const d = Math.max(p.x - startP.x, (p.y - startP.y) * frame.aspect)
                            frame.width = Math.max(40, startW + d)
                            frame.height = frame.width / frame.aspect
                        }
                    }
                }
            }

            // edit-mode banner
            Rectangle {
                visible: root.editing
                anchors.top: parent.top
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: hint.implicitWidth + 32
                height: hint.implicitHeight + 16
                radius: 8
                color: "#e61e3a8a"
                Text {
                    id: hint
                    anchors.centerIn: parent
                    color: "white"
                    font.pixelSize: 14
                    text: "TRACE EDIT  ·  drag: move  ·  corner: resize  ·  ctrl+scroll: size  ·  scroll: opacity ("
                          + Math.round(root.alpha * 100) + "%)  ·  H/V: flip  ·  R/shift+R: rotate 90°  ·  alt+scroll: rotate ("
                          + Math.round(root.rot) + "°)  ·  0: unrotate  ·  Esc / right-click / double-click: done"
                }
            }
        }
    }

    // Driven by `quickshell ipc -p <this file> call trace <fn>`
    IpcHandler {
        target: "trace"
        function edit(): void { root.shown = true; root.editing = !root.editing }
        function done(): void { root.editing = false }
        function more(): void { root.alpha = Math.min(1.0, root.alpha + 0.1) }
        function less(): void { root.alpha = Math.max(0.05, root.alpha - 0.1) }
        function hide(): void { root.shown = !root.shown }
        function fliph(): void { root.flipH = !root.flipH }
        function flipv(): void { root.flipV = !root.flipV }
        function load(path: string): void { root.img = path }
    }
}
