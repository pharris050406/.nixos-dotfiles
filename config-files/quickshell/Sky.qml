import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The live sky as your wallpaper: SkyView on the background layer, under
// every window. You see it on any empty workspace.
//   scroll over the sky: turn            scroll over the ground: run time
//   hold right button + scroll: zoom     middle-click: back to now
// (No Shift/Ctrl: a wallpaper never has keyboard focus, so Wayland never
// tells it which modifier keys are held.)
//   hover a planet, the Sun, the Moon or a named star: what it is
// Where you're facing and the zoom are remembered across restarts.
PanelWindow {
    id: sky

    property Theme theme
    property real latitude: 34.05
    property real longitude: -118.25
    property real warp: 0                       // minutes; deliberately not saved

    // Where you're looking lives here. The file is only a save slot, written
    // once you stop scrolling. (The view used to be bound straight to the file:
    // every wheel step wrote it, every write triggered a reload, and a reload
    // that landed late put an older angle back, so fast scrolling jumped.)
    property real facing: 180                   // south: where the planets and the Moon pass
    property real fov: 150
    property bool touched: false

    function look(f, v) {
        touched = true;
        facing = f;
        fov = v;
        save.restart();
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: theme.background

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "deepfield-sky"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    FileView {
        id: store
        path: Quickshell.statePath("sky.json")
        blockLoading: true
        onLoaded: if (!sky.touched) { sky.facing = prefs.facing; sky.fov = prefs.fov; }
        JsonAdapter {
            id: prefs
            property real facing: 180
            property real fov: 150
        }
    }
    Component.onCompleted: if (!touched) { facing = prefs.facing; fov = prefs.fov; }

    Timer {
        id: save
        interval: 800
        onTriggered: {
            prefs.facing = sky.facing;
            prefs.fov = sky.fov;
            store.writeAdapter();
        }
    }

    SkyView {
        anchors.fill: parent
        theme: sky.theme
        latitude: sky.latitude
        longitude: sky.longitude
        facing: sky.facing
        fov: sky.fov
        offsetMin: sky.warp
        meteors: Motion.live                    // off on battery, with the rest of the motion
        onTurned: f => sky.look(f, sky.fov)
        onZoomed: f => sky.look(sky.facing, f)
        onWarped: m => sky.warp = m
    }
}
