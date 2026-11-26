import QtQuick

Item {
    id: root

    property color background: "#181825"
    property color foreground: "#cdd6f4"
    property color muted: "#585b70"
    property color accent1: "#81c8be"
    property color accent2: "#8caaee"
    property color accent3: "#a6d189"
    property color accent4: "#e5c890"
    property color accent5: "#ef9f76"
    property color accent6: "#e78284"
    property color accent7: "#ca9ee6"

    property color barColor: "#181825"
    property real barOpacity: 0.85

    property string fontFamily: "JetBrainsMono Nerd Font"
    // Everything in the bar (text, orbits, instruments) scales off fontSize;
    // it also sizes the cards, notifications, picker and sky labels.
    property int fontSize: 11
    // Bar thickness = fontSize + barPadding. Was 13 + 21 = 34 px.
    // 12 + 16 = 28 is the laptop default; 12 + 14 = 26 and 11 + 13 = 24 still fit.
    property int barPadding: 10
    readonly property int barHeight: fontSize + barPadding
}
