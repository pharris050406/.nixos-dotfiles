#!/bin/sh
# Streams one *pinned* player's state to the Quickshell MusicWidget.
# The pin lives in a state file and only changes when media-ctl.sh cycles it.
#
# Protocol (unchanged): META|<Status>|<lengthMicro>|<track>   POS|<seconds>

CACHE="$HOME/.cache/quickshell"
STATE="$CACHE/selected-player"
PIDFILE="$CACHE/media-source.pid"
FMT='META|{{status}}|{{mpris:length}}|{{title}} - {{artist}}'
IDLE='META|Stopped|0|Not Playing'

mkdir -p "$CACHE"

# Only one of us at a time. A copy left over from an earlier bar (a reload,
# a crash) is told to stop, and its trap takes its playerctl down with it.
old=$(cat "$PIDFILE" 2>/dev/null)
if [ -n "$old" ] && [ "$old" != $$ ] && ps -o command= -p "$old" 2>/dev/null | grep -q media-source; then
    kill "$old" 2>/dev/null
fi
echo $$ > "$PIDFILE"
PARENT=$PPID        # the bar (Media.qml execs us directly)

# Every synchronous playerctl call is wrapped in timeout: a hung D-Bus Get
# would otherwise stall this whole loop and freeze the widget indefinitely.
# playerctld is filtered out - it lists itself, and pinning it means MRU.
list_players() {
    timeout 2 playerctl -l 2>/dev/null | grep -vx playerctld | sort
}

# Pinned player if alive; else same app with a new instance suffix
# (firefox.instance_1_3 -> firefox.instance_2_7); else first available.
current_player() {
    _list=$(list_players)
    [ -z "$_list" ] && return
    _pin=$(cat "$STATE" 2>/dev/null)
    if [ -n "$_pin" ]; then
        if printf '%s\n' "$_list" | grep -qxF "$_pin"; then
            printf '%s\n' "$_pin"
            return
        fi
        _match=$(printf '%s\n' "$_list" |
            awk -v b="${_pin%%.*}" 'index($0, b) == 1 { print; exit }')
        if [ -n "$_match" ]; then
            printf '%s\n' "$_match" > "$STATE"
            printf '%s\n' "$_match"
            return
        fi
    fi
    printf '%s\n' "$_list" | head -n 1
}

FOLLOW_PID=

stop_follow() {
    [ -n "$FOLLOW_PID" ] && kill "$FOLLOW_PID" 2>/dev/null
    FOLLOW_PID=
}

# --follow blocks and emits metadata on every change (instant). Backgrounded
# directly so $! is playerctl's own pid and it can be killed cleanly.
# A small watchdog takes it down if this script is ever killed outright
# (SIGKILL runs no trap): that's how they piled up, one per bar reload.
# (Quickshell ignores SIGPIPE and children inherit that, so a follower
# writing into a closed pipe doesn't die by itself either.)
start_follow() {
    [ -z "$1" ] && return
    playerctl -p "$1" --follow metadata --format "$FMT" 2>/dev/null &
    FOLLOW_PID=$!
    _f=$FOLLOW_PID
    ( while kill -0 $$ 2>/dev/null && kill -0 "$_f" 2>/dev/null; do sleep 5; done
      kill "$_f" 2>/dev/null ) >/dev/null 2>&1 &
}

# Write a line, or stop once nobody's reading (bar reloaded or gone).
say() { printf '%s\n' "$1" 2>/dev/null || exit 0; }

trap 'stop_follow' EXIT
trap 'stop_follow; exit 0' INT TERM HUP PIPE

PLAYER=$(current_player)
if [ -n "$PLAYER" ]; then
    start_follow "$PLAYER"
else
    say "$IDLE"
fi

tick=0
woke=no
while :; do
    # The bar is gone (killed hard, so no signal reached us): stop too.
    kill -0 "$PARENT" 2>/dev/null || exit 0

    # Which player: every 5 s, at once when media-ctl.sh cuts our sleep short
    # (cycling players), or when the follower died. Was every second; each
    # look costs four processes.
    restart=no
    if [ "$woke" = yes ] || [ $((tick % 5)) -eq 0 ]; then
        new=$(current_player)
        [ "$new" != "$PLAYER" ] && restart=yes
    else
        new=$PLAYER
    fi
    if [ -n "$FOLLOW_PID" ] && ! kill -0 "$FOLLOW_PID" 2>/dev/null; then
        restart=yes          # follower died (player quit, bridge restarted)
        new=$(current_player)
    fi

    if [ "$restart" = yes ]; then
        stop_follow
        PLAYER=$new
        if [ -n "$PLAYER" ]; then
            start_follow "$PLAYER"
        else
            say "$IDLE"
        fi
    fi

    # Position: only while playing (the bar counts the seconds itself
    # between reports), plus once when it pauses so the bar stops in the
    # right place. Status and position in one call.
    if [ -n "$PLAYER" ]; then
        sp=$(timeout 2 playerctl -p "$PLAYER" metadata --format '{{status}} {{position}}' 2>/dev/null)
        st=${sp%% *}
        us=${sp#* }
        if [ "$st" = Playing ] || [ "$st" != "$last" ]; then
            case $us in
                ''|*[!0-9]*) ;;
                *) say "POS|$((us / 1000000))" ;;
            esac
        fi
        last=$st
    fi

    tick=$((tick + 1))
    woke=no
    sleep 1 || woke=yes     # media-ctl.sh may kill the sleep to switch players now
done
