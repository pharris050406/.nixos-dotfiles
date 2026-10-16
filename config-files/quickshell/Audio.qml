pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Output volume and mute for the default sink, through Quickshell's native
// PipeWire service: no polling, and changes made anywhere else (wpctl
// keybinds, pavucontrol, a headphone plug switching sinks) arrive as events.
//
//   volume        0..100 (can read above 100 if something else boosted it)
//   muted
//   dragging      set by the gain slider while it's held
//   setVolume(v)  clamped to 0..100, or to the current level if that's higher
//   toggleMute()
//   externalChange()  fired when the level or mute changes and it wasn't us
Singleton {
    id: audio

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null && sink.ready

    // The sink's volume/mute are only valid while it's bound.
    PwObjectTracker { objects: [audio.sink] }

    readonly property int volume: ready ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: ready ? sink.audio.muted : false
    property bool dragging: false

    signal externalChange()

    // Our own changes come back from PipeWire as change events too. Anything
    // that lands well after our last write came from somewhere else.
    // Not armed until a sink has been bound for a second, so the first real
    // values arriving at startup don't count as a change.
    property real _lastLocal: 0
    property bool _armed: false
    onReadyChanged: if (ready) armTimer.restart(); else _armed = false
    Timer { id: armTimer; interval: 1000; onTriggered: audio._armed = true }

    function _changed() {
        if (_armed && Date.now() - _lastLocal > 500) externalChange();
    }
    onVolumeChanged: _changed()
    onMutedChanged: _changed()
    // A different sink (headphones plugged in, Bluetooth connected) is news too.
    onSinkChanged: _changed()

    function setVolume(v) {
        if (!ready) return;
        var hi = Math.max(100, volume);
        v = Math.max(0, Math.min(hi, Math.round(v)));
        _lastLocal = Date.now();
        sink.audio.volume = v / 100;
    }
    function toggleMute() {
        if (!ready) return;
        _lastLocal = Date.now();
        sink.audio.muted = !sink.audio.muted;
    }
}
