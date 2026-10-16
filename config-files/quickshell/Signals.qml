import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "Lib.js" as Lib

// Notification popups, as incoming transmissions. They stack under the bar
// at the top right, in the same card style as the bar's hover cards.
//  - The 2px rule is the urgency: blue normal, grey low, red (pulsing) critical;
//    gold for sky events (Events.qml), like the ephemeris card that lists them.
//  - "T+0:12" counts up from reception, like mission time.
//  - A thin line along the bottom drains as the timeout runs; hovering holds it.
//    Critical ones never time out.
//  - Click: the default action (or dismiss). Right-click: dismiss.
//    Middle-click: dismiss everything. Action buttons appear when the app sends them.
// A replaced notification (same id, e.g. a progress update) refreshes in place
// and restarts its timer.
PanelWindow {
    id: sig

    property Theme theme
    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)

    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    exclusionMode: ExclusionMode.Normal      // sit below the bar
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight)
    visible: rep.count > 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "deepfield-signals"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: stack
        width: parent.width
        spacing: 8

        Repeater {
            id: rep
            model: Notifs.live

            Item {
                id: card
                required property var modelData
                readonly property var n: modelData
                readonly property bool critical: !!n && n.urgency === NotificationUrgency.Critical
                readonly property bool low: !!n && n.urgency === NotificationUrgency.Low
                readonly property bool sky: !!n && n.appName === "deepfield sky"
                readonly property color accent: critical ? sig.theme.accent6 : sky ? sig.theme.accent4
                                              : low ? sig.theme.muted : sig.theme.accent2
                readonly property bool hasImage: !!n && n.image !== ""
                // `actions` is a QML list, so go through Array.prototype explicitly.
                readonly property var buttons: n ? Array.prototype.filter.call(n.actions, a => a.identifier !== "default") : []
                readonly property var defaultAction: n ? Array.prototype.find.call(n.actions, a => a.identifier === "default") : undefined

                // ms. Apps ask in ms on the wire (notify-send -t 2500); Quickshell's
                // docs say expireTimeout is seconds. Accept either: nobody asks for a
                // popup lasting over 10 minutes, so anything above 600 is ms.
                readonly property real askedMs: !n || n.expireTimeout <= 0 ? 0
                    : n.expireTimeout > 600 ? n.expireTimeout : n.expireTimeout * 1000
                readonly property real lifetime: critical ? 0
                    : askedMs > 0 ? Math.min(120000, Math.max(1500, askedMs))
                    : low ? 4000 : 7000

                property real born: 0
                property int age: 0
                property real remaining: 1
                property bool leaving: false

                width: stack.width
                height: face.height
                clip: true

                Component.onCompleted: {
                    born = Date.now();
                    enter.start();
                    if (lifetime > 0) countdown.start();
                }

                function close(dismissed) {
                    if (leaving) return;
                    leaving = true;
                    exit.dismissed = dismissed;
                    exit.start();
                }

                // A replaced notification refreshes in place.
                Connections {
                    target: card.n
                    function onSummaryChanged() { card.refresh(); }
                    function onBodyChanged() { card.refresh(); }
                }
                function refresh() {
                    born = Date.now();
                    age = 0;
                    if (lifetime > 0) countdown.restart();
                }

                Timer {
                    interval: 1000; repeat: true; running: !card.leaving
                    onTriggered: card.age = Math.floor((Date.now() - card.born) / 1000)
                }

                NumberAnimation {
                    id: countdown
                    target: card; property: "remaining"
                    from: 1; to: 0
                    duration: Math.max(1, card.lifetime)
                    paused: running && hover.hovered
                    onFinished: if (card.remaining <= 0.001) card.close(false)
                }

                NumberAnimation {
                    id: enter
                    target: face; property: "x"
                    from: stack.width + 20; to: 0
                    duration: 260; easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    id: exit
                    property bool dismissed: false
                    ParallelAnimation {
                        NumberAnimation { target: face; property: "x"; to: stack.width + 20; duration: 200; easing.type: Easing.InCubic }
                        NumberAnimation { target: face; property: "opacity"; to: 0; duration: 200 }
                    }
                    ScriptAction {
                        script: {
                            if (!card.n) return;
                            if (exit.dismissed) card.n.dismiss(); else card.n.expire();
                        }
                    }
                }

                Rectangle {
                    id: face
                    width: card.width
                    height: inner.implicitHeight + 28
                    color: Qt.rgba(sig.theme.barColor.r, sig.theme.barColor.g, sig.theme.barColor.b, 0.92)
                    border.width: 1
                    border.color: Lib.mix(sig.theme.muted, sig.theme.barColor, 0.35)

                    HoverHandler { id: hover }

                    // urgency rule
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 2
                        color: card.accent
                        SequentialAnimation on opacity {
                            running: card.critical
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 650; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: m => {
                            if (m.button === Qt.MiddleButton) Notifs.dismissAll();
                            else if (m.button === Qt.RightButton) card.close(true);
                            else if (card.defaultAction) card.defaultAction.invoke();
                            else card.close(true);
                        }
                    }

                    Row {
                        id: inner
                        x: 14; y: 16
                        spacing: 12

                        Image {
                            visible: card.hasImage
                            width: 44; height: 44
                            source: card.hasImage ? card.n.image : ""
                            sourceSize { width: 88; height: 88 }
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Column {
                            width: card.width - 28 - (card.hasImage ? 56 : 0)
                            spacing: 4

                            Item {
                                width: parent.width
                                height: head.implicitHeight
                                Text {
                                    id: head
                                    text: ((card.critical ? "priority transmission" : "transmission")
                                           + (card.n && card.n.appName ? " · " + card.n.appName : "")).toUpperCase()
                                    width: parent.width - tplus.implicitWidth - 10
                                    elide: Text.ElideRight
                                    color: card.accent
                                    font { family: sig.theme.fontFamily; pixelSize: sig.theme.fontSize - 3; letterSpacing: 2; bold: true }
                                }
                                Text {
                                    id: tplus
                                    anchors { right: parent.right; baseline: head.baseline }
                                    text: "T+" + Lib.clock(card.age)
                                    color: sig.label
                                    font { family: sig.theme.fontFamily; pixelSize: sig.theme.fontSize - 3 }
                                }
                            }
                            Text {
                                width: parent.width
                                text: card.n ? card.n.summary : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: sig.theme.foreground
                                font { family: sig.theme.fontFamily; pixelSize: sig.theme.fontSize; bold: true }
                            }
                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: card.n ? card.n.body : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                color: sig.label
                                font { family: sig.theme.fontFamily; pixelSize: sig.theme.fontSize - 1 }
                            }
                            Flow {
                                visible: card.buttons.length > 0
                                width: parent.width
                                spacing: 6
                                topPadding: 4
                                Repeater {
                                    model: card.buttons
                                    Rectangle {
                                        id: btn
                                        required property var modelData
                                        width: btnText.implicitWidth + 20
                                        height: btnText.implicitHeight + 8
                                        radius: height / 2
                                        color: btnMouse.containsMouse ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.18) : "transparent"
                                        border.width: 1
                                        border.color: card.accent
                                        Text {
                                            id: btnText
                                            anchors.centerIn: parent
                                            text: btn.modelData.text
                                            color: sig.theme.foreground
                                            font { family: sig.theme.fontFamily; pixelSize: sig.theme.fontSize - 2 }
                                        }
                                        MouseArea {
                                            id: btnMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: btn.modelData.invoke()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // timeout, draining
                    Rectangle {
                        visible: card.lifetime > 0
                        anchors { bottom: parent.bottom; left: parent.left }
                        width: Math.round(parent.width * card.remaining)
                        height: 2
                        color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, hover.hovered ? 0.35 : 0.7)
                    }
                }
            }
        }
    }
}
