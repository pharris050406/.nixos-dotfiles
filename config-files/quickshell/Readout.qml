import QtQuick
import "Lib.js" as Lib

// key   value     (one line of an instrument card)
Row {
    id: ro

    property Theme theme
    property string k: ""
    property string v: ""
    property bool hot: false
    property bool dim: false
    property int keyWidth: 76

    spacing: 8

    Text {
        width: ro.keyWidth
        text: ro.k
        color: Lib.mix(ro.theme.foreground, ro.theme.muted, 0.5)
        font { family: ro.theme.fontFamily; pixelSize: ro.theme.fontSize - 1 }
    }
    Text {
        text: ro.v
        color: ro.hot ? ro.theme.accent6 : ro.dim ? Lib.mix(ro.theme.foreground, ro.theme.muted, 0.5) : ro.theme.foreground
        font { family: ro.theme.fontFamily; pixelSize: ro.theme.fontSize - 1 }
    }
}
