import QtQuick
import Quickshell
import "Lib.js" as Lib

// The one popup surface every hover card uses. Set `want` from a hover and it
// handles the rest: a short open delay (so sweeping the cursor across the bar
// doesn't strobe cards), a shorter close delay, and a small drop-in.
// `heading` draws a letterspaced instrument label across the top.
PopupWindow {
    id: card

    property Theme theme
    property Item target
    property bool want: false
    property bool alignRight: false
    property color accent: theme.muted
    property string heading: ""
    property string subheading: ""
    property int openDelay: 220
    property int closeDelay: 120
    property int pad: 14
    default property alias content: body.data

    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)

    visible: false
    color: "transparent"
    width: Math.max(body.implicitWidth, head.visible ? head.implicitWidth : 0) + 2 * pad
    height: stack.implicitHeight + 2 * pad + 2

    anchor {
        item: card.target
        edges: card.alignRight ? (Edges.Bottom | Edges.Right) : Edges.Bottom
        gravity: card.alignRight ? (Edges.Bottom | Edges.Left) : Edges.Bottom
    }
    // Anchors don't follow a moved/changed item on their own.
    onTargetChanged: if (visible) anchor.updateAnchor()

    onWantChanged: {
        if (want) { closeT.stop(); if (!visible) openT.restart(); }
        else { openT.stop(); if (visible) closeT.restart(); }
    }
    Timer { id: openT; interval: card.openDelay; onTriggered: card.visible = true }
    Timer { id: closeT; interval: card.closeDelay; onTriggered: card.visible = false }

    onVisibleChanged: if (visible) drop.restart()
    ParallelAnimation {
        id: drop
        NumberAnimation { target: surface; property: "opacity"; from: 0; to: 1; duration: 140 }
        NumberAnimation { target: surface; property: "y"; from: -4; to: 0; duration: 180; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: surface
        width: parent.width
        height: parent.height
        // Opaque, so the wallpaper can't bleed through and wash out the text.
        color: Qt.rgba(card.theme.barColor.r, card.theme.barColor.g, card.theme.barColor.b, 1)
        border.width: 1
        border.color: Lib.mix(card.theme.muted, card.theme.barColor, 0.35)

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2
            color: card.accent
        }

        Column {
            id: stack
            x: card.pad
            y: card.pad + 2
            spacing: 8

            Item {
                id: head
                visible: card.heading !== ""
                width: Math.max(implicitWidth, body.implicitWidth)
                implicitWidth: headText.implicitWidth + (subText.text ? subText.implicitWidth + 24 : 0)
                implicitHeight: headText.implicitHeight
                Text {
                    id: headText
                    text: card.heading.toUpperCase()
                    color: card.accent
                    font { family: card.theme.fontFamily; pixelSize: card.theme.fontSize - 3; letterSpacing: 2.5; bold: true }
                }
                Text {
                    id: subText
                    anchors { right: parent.right; baseline: headText.baseline }
                    text: card.subheading
                    color: card.label
                    font { family: card.theme.fontFamily; pixelSize: card.theme.fontSize - 2 }
                }
            }

            Column {
                id: body
                spacing: 6
            }
        }
    }
}
