import QtQuick
import "Lib.js" as Lib

// An outlined word that slides out when `on`, and folds away when it isn't.
// While folding it keeps showing its last text, so it doesn't blank mid-exit.
Item {
    id: chip

    property Theme theme
    property bool on: false
    property string text: ""
    property color ink: theme.accent6
    property bool pulse: false

    property string _shown: ""
    onTextChanged: if (on) _shown = text
    onOnChanged: if (on) _shown = text

    readonly property real full: Math.ceil(label.implicitWidth) + 18

    width: on ? full + 8 : 0
    height: theme.fontSize + 6
    visible: width > 0.5
    clip: true
    opacity: on ? 1 : 0
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Rectangle {
        id: pill
        width: chip.full
        height: chip.height
        radius: height / 2
        color: Qt.rgba(chip.ink.r, chip.ink.g, chip.ink.b, 0.12)
        border.width: 1
        border.color: chip.ink

        SequentialAnimation on opacity {
            running: chip.pulse && chip.on
            loops: Animation.Infinite
            onRunningChanged: if (!running) pill.opacity = 1
            NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 800; easing.type: Easing.InOutSine }
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: chip._shown
            color: chip.ink
            font { family: chip.theme.fontFamily; pixelSize: chip.theme.fontSize - 1 }
        }
    }
}
