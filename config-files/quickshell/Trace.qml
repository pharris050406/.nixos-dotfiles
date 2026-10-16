import QtQuick
import QtQuick.Layouts
import "Lib.js" as Lib

// name   ╱╲__╱╲___ (graph)   value
RowLayout {
    id: tr

    property Theme theme
    property string name: ""
    property var values: []
    property color tint: "white"
    property string value: ""
    property bool hot: false
    property int keyWidth: 76

    implicitWidth: 340
    spacing: 8

    Text {
        Layout.preferredWidth: tr.keyWidth
        text: tr.name
        color: Lib.mix(tr.theme.foreground, tr.theme.muted, 0.5)
        font { family: tr.theme.fontFamily; pixelSize: tr.theme.fontSize - 1 }
    }
    Spark {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
        values: tr.values
        tint: tr.hot ? tr.theme.accent6 : tr.tint
        baseColor: tr.theme.muted
    }
    Text {
        Layout.preferredWidth: 92
        horizontalAlignment: Text.AlignRight
        text: tr.value
        color: tr.hot ? tr.theme.accent6 : tr.theme.foreground
        font { family: tr.theme.fontFamily; pixelSize: tr.theme.fontSize - 1 }
    }
}
