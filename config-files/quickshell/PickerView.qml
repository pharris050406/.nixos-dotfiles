import QtQuick
import "Lib.js" as Lib

// The picker's contents: a heading, a line to type in, and the matches.
// Picker.qml puts this on screen; everything here is plain QtQuick.
//
// Matching is dmenu's: every space-separated word must appear somewhere in
// the item, and items equal to what you typed come first, then items that
// start with it, then the rest, each group in its original order.
//
//   enter         pick the highlighted item (or what you typed, if nothing matches)
//   shift+enter   return exactly what you typed
//   tab           copy the highlighted item into the input
//   ↑/↓  ctrl+p/n  ctrl+k/j   move        pgup/pgdn  move a page
//   ctrl+u        clear       ctrl+w  delete a word        esc / ctrl+c  cancel
Item {
    id: view

    property Theme theme
    property string prompt: ""
    property bool caseInsensitive: true
    property bool loading: false
    property int maxRows: 12
    // Rows the list area takes up. Set once per opening, from how many items
    // there are, and then left alone: the panel never resizes while you type
    // (a resize is a new buffer, and that's what reads as a flicker).
    property int rows: 12

    signal accepted(string text)
    signal canceled()

    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)
    readonly property color edge: Lib.mix(theme.muted, theme.barColor, 0.35)
    // (Read input.text, not this, inside onTextChanged: a binding can lag a
    // handler on the same signal.)
    readonly property string query: input.text

    // The list itself lives in plain JS arrays: no bindings to update per item.
    property var _items: []
    property var _hay: []            // lowercased copy when case-insensitive
    property var _all: []            // 0..n-1, reused for an empty query
    property var results: []         // indices into _items, best first
    property int sel: 0
    // The list shows the best `shown` matches. Rebuilding a 20,000-row model on
    // every keystroke is what would make typing lag; nobody scrolls past 500.
    readonly property int shown: Math.min(results.length, 500)
    property var visibleResults: []

    function reset(prompt, ci, rows) {
        // Empty the list before the arrays it points into, or its rows would
        // briefly look up items that are gone.
        visibleResults = []; results = [];
        _items = []; _hay = []; _all = [];
        view.prompt = prompt;
        caseInsensitive = ci;
        maxRows = rows > 0 ? rows : 12;
        view.rows = maxRows;
        sel = 0;
        loading = true;
        input.text = "";
        input.forceActiveFocus();
    }

    function setItems(list) {
        var n = list.length, hay = new Array(n), all = new Array(n);
        for (var i = 0; i < n; i++) {
            hay[i] = caseInsensitive ? list[i].toLowerCase() : list[i];
            all[i] = i;
        }
        _items = list; _hay = hay; _all = all;
        rows = Math.max(1, Math.min(n, maxRows));
        loading = false;
        refilter();
    }

    function focusInput() { input.forceActiveFocus(); }

    function refilter() {
        var text = input.text;
        var q = caseInsensitive ? text.toLowerCase() : text;
        var words = q.split(/\s+/).filter(w => w !== "");
        if (words.length === 0) {
            results = _all;
        } else {
            var exact = [], prefix = [], rest = [], hay = _hay, nw = words.length;
            for (var i = 0, n = hay.length; i < n; i++) {
                var h = hay[i], ok = true;
                for (var k = 0; k < nw; k++)
                    if (h.indexOf(words[k]) < 0) { ok = false; break; }
                if (!ok) continue;
                if (h === q) exact.push(i);
                else if (h.startsWith(q)) prefix.push(i);
                else rest.push(i);
            }
            results = exact.concat(prefix, rest);
        }
        visibleResults = results.length > 500 ? results.slice(0, 500) : results;
        sel = 0;
        list.positionViewAtBeginning();
    }

    function move(d) {
        if (shown === 0) return;
        sel = Math.max(0, Math.min(shown - 1, sel + d));
        list.positionViewAtIndex(sel, ListView.Contain);
    }

    function current() { return results.length > 0 ? _items[results[sel]] : ""; }

    function submit(typedOnly) {
        if (!typedOnly && results.length > 0) accepted(current());
        else if (input.text !== "") accepted(input.text);
    }

    // Item text with every typed word highlighted where it first occurs.
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function markup(i, ink) {
        var text = _items[i], h = _hay[i];
        if (text === undefined) return "";
        var typed = input.text;
        var words = (caseInsensitive ? typed.toLowerCase() : typed).split(/\s+/).filter(w => w !== "");
        if (words.length === 0) return esc(text);
        var spans = [];
        for (var k = 0; k < words.length; k++) {
            var at = h.indexOf(words[k]);
            if (at >= 0) spans.push([at, at + words[k].length]);
        }
        spans.sort((a, b) => a[0] - b[0]);
        var out = "", pos = 0;
        for (var s = 0; s < spans.length; s++) {
            var a = Math.max(spans[s][0], pos), b = spans[s][1];
            if (b <= pos) continue;
            out += esc(text.slice(pos, a)) + "<font color=\"" + ink + "\">" + esc(text.slice(a, b)) + "</font>";
            pos = b;
        }
        return out + esc(text.slice(pos));
    }

    readonly property var dust: {
        var rnd = Lib.rng(2001), out = [];
        for (var i = 0; i < 360; i++) {
            var x = rnd() * 760, y = rnd() * 640, b = Math.pow(rnd(), 4);
            out.push({ x: x, y: y, s: b > 0.6 ? 2 : 1, a: 0.15 + 0.75 * b,
                       c: Lib.blackbody(2600 + Math.pow(rnd(), 2.2) * 14000) });
        }
        return out;
    }

    FontMetrics { id: fm; font.family: view.theme.fontFamily; font.pixelSize: view.theme.fontSize }
    readonly property int rowH: Math.ceil(fm.height) + 8
    readonly property int pad: 14

    implicitHeight: frame.height

    Rectangle {
        id: frame
        width: parent.width
        height: body.implicitHeight + 2 * view.pad + 2
        color: Qt.rgba(view.theme.barColor.r, view.theme.barColor.g, view.theme.barColor.b, 1)
        border.width: 1
        border.color: view.edge
        clip: true

        // A faint scatter of stars behind the list, same recipe as the bar's
        // (blackbody colors, mostly faint). Plain rectangles laid out once, not
        // a Canvas: a Canvas can paint a frame late when the panel opens.
        Item {
            anchors.fill: parent
            opacity: 0.6
            Repeater {
                model: view.dust
                Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y
                    width: modelData.s; height: modelData.s
                    radius: modelData.s / 2
                    color: modelData.c
                    opacity: modelData.a
                }
            }
        }

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2
            color: view.theme.accent2
        }

        Column {
            id: body
            x: view.pad
            y: view.pad + 2
            width: parent.width - 2 * view.pad
            spacing: 8

            // heading: PROMPT ............................ 12 / 4812
            Item {
                width: parent.width
                height: head.implicitHeight
                Text {
                    id: head
                    text: (view.prompt || "select").toUpperCase()
                    color: view.theme.accent2
                    font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize - 3; letterSpacing: 2.5; bold: true }
                }
                Text {
                    anchors { right: parent.right; baseline: head.baseline }
                    text: view.loading ? "receiving…"
                        : view.query === "" ? view._items.length + ""
                        : view.results.length + " / " + view._items.length
                          + (view.results.length > view.shown ? " (best " + view.shown + ")" : "")
                    color: view.label
                    font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize - 2 }
                }
            }

            // input
            Item {
                width: parent.width
                height: view.rowH
                Text {
                    id: caret
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    color: view.theme.accent2
                    font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize + 2; bold: true }
                }
                TextInput {
                    id: input
                    anchors { left: caret.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
                    color: view.theme.foreground
                    selectionColor: view.theme.accent2
                    selectedTextColor: view.theme.barColor
                    cursorVisible: activeFocus
                    clip: true
                    font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize + 1 }
                    onTextChanged: view.refilter()

                    Keys.onPressed: e => {
                        var ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                        switch (e.key) {
                        case Qt.Key_Escape: view.canceled(); break;
                        case Qt.Key_Return: case Qt.Key_Enter:
                            view.submit((e.modifiers & Qt.ShiftModifier) !== 0); break;
                        case Qt.Key_Tab:
                            if (view.results.length > 0) { text = view.current(); cursorPosition = text.length; }
                            break;
                        case Qt.Key_Down: view.move(1); break;
                        case Qt.Key_Up: view.move(-1); break;
                        case Qt.Key_PageDown: view.move(view.maxRows); break;
                        case Qt.Key_PageUp: view.move(-view.maxRows); break;
                        default:
                            if (!ctrl) return;
                            switch (e.key) {
                            case Qt.Key_N: case Qt.Key_J: view.move(1); break;
                            case Qt.Key_P: case Qt.Key_K: view.move(-1); break;
                            case Qt.Key_C: view.canceled(); break;
                            case Qt.Key_U: text = ""; break;
                            case Qt.Key_W: {
                                var before = text.slice(0, cursorPosition).replace(/\S+\s*$/, "");
                                var after = text.slice(cursorPosition);
                                text = before + after;
                                cursorPosition = before.length;
                                break;
                            }
                            default: return;
                            }
                        }
                        e.accepted = true;
                    }
                }
                Text {
                    anchors { left: input.left; verticalCenter: parent.verticalCenter }
                    visible: input.text === ""
                    text: "type to filter"
                    color: view.theme.muted
                    font: input.font
                }
            }

            Rectangle { width: parent.width; height: 1; color: view.edge }

            Item {
                // fixed height for the whole opening; the list scrolls inside it
                width: parent.width
                height: view.rows * view.rowH

                Text {
                    visible: list.count === 0
                    height: view.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: view.loading ? "…" : view.query === "" ? "nothing to pick from" : "no matches · shift+enter sends what you typed"
                    color: view.theme.muted
                    font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: view.visibleResults
                    currentIndex: view.sel
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds
                    reuseItems: true

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === view.sel
                        width: list.width
                        height: view.rowH

                        Rectangle {
                            anchors.fill: parent
                            visible: row.selected
                            color: Qt.rgba(view.theme.accent2.r, view.theme.accent2.g, view.theme.accent2.b, 0.14)
                            Rectangle { width: 2; height: parent.height; color: view.theme.accent2 }
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            text: view.markup(row.modelData, row.selected ? view.theme.accent2 : view.theme.accent4)
                            textFormat: Text.StyledText
                            elide: Text.ElideRight
                            color: row.selected ? view.theme.foreground : Lib.mix(view.theme.foreground, view.theme.muted, 0.25)
                            font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize; bold: row.selected }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: view.sel = row.index
                            onClicked: view.submit(false)
                        }
                    }
                }
            }

            Text {
                text: "enter pick   shift+enter typed   tab complete   esc"
                color: view.theme.muted
                font { family: view.theme.fontFamily; pixelSize: view.theme.fontSize - 3 }
            }
        }
    }
}
