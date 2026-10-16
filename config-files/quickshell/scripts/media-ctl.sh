#!/bin/sh
# Media controls for the pinned player. The pin only changes on `cycle`.
# Usage: media-ctl.sh {play-pause|next|previous|cycle}

CACHE="$HOME/.cache/quickshell"
STATE="$CACHE/selected-player"
PIDFILE="$CACHE/media-source.pid"

mkdir -p "$CACHE"

notify_cmd() { command -v notify-send >/dev/null 2>&1; }

list_players() {
    timeout 2 playerctl -l 2>/dev/null | grep -vx playerctld | sort
}

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

# Wake media-source.sh immediately by killing the sleep it is blocked in.
poke_source() {
    _sp=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$_sp" ] && pkill -P "$_sp" sleep 2>/dev/null
    return 0
}

PLAYER=$(current_player)

if [ "$1" = cycle ]; then
    list=$(list_players)
    if [ -z "$list" ]; then
        notify_cmd && notify-send -a media -t 2000 \
            -h string:x-canonical-private-synchronous:media \
            "Media Focus" "No players found"
        exit 0
    fi
    next=$(printf '%s\n' "$list" | awk -v cur="$PLAYER" '
        { a[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++)
                if (a[i] == cur) { print a[i % NR + 1]; exit }
            print a[1]
        }')
    printf '%s\n' "$next" > "$STATE"
    poke_source
    notify_cmd && notify-send -a "${next%%.*}" -t 1500 \
        -h string:x-canonical-private-synchronous:media \
        "Media Focus" "Now controlling: $next"
    exit 0
fi

[ -z "$PLAYER" ] && exit 0

pc() { timeout 2 playerctl -p "$PLAYER" "$@" 2>/dev/null; }
title_now() { pc metadata --format '{{title}}'; }

state=""        # what the player is doing after the key, if we know already
old=""          # the title before a skip, to wait for the new one
case "$1" in
    play-pause)
        # Ask first and invert: right after the toggle the player may not
        # have published its new status yet.
        case "$(pc status)" in
            Playing) state=Paused ;;
            *)       state=Playing ;;
        esac
        pc play-pause
        ;;
    next)
        old=$(title_now)
        pc next
        ;;
    previous)
        pos=$(pc position)
        posint=${pos%.*}
        if [ "${posint:-0}" -gt 5 ] 2>/dev/null; then
            pc position 0   # restart track
        else
            old=$(title_now)
            pc previous
        fi
        ;;
    *)
        echo "usage: $0 {play-pause|next|previous|cycle}" >&2
        exit 1
        ;;
esac

poke_source

# --- notification with album art (best effort) ---
notify_cmd || exit 0

# After a skip, give the player up to ~1s to publish the new track, so the
# notification doesn't announce the song you just left.
if [ -n "$old" ]; then
    i=0
    while [ "$i" -lt 20 ] && [ "$(title_now)" = "$old" ]; do
        sleep 0.05
        i=$((i + 1))
    done
fi

title=$(title_now)
[ -z "$title" ] && exit 0
artist=$(pc metadata --format '{{artist}}')
art=$(pc metadata mpris:artUrl)
[ -z "$state" ] && state=$(pc status)

case "$state" in
    Playing) state=playing ;;
    Paused)  state=paused ;;
    Stopped) state=stopped ;;
esac
body=$artist
[ -n "$state" ] && body="${artist:+$artist · }$state"

icon=audio-x-generic
case "$art" in
    https://i.scdn.co/*|https://*.mzstatic.com/*)
        curl -s --max-filesize 2000000 --connect-timeout 2 "$art" \
            -o /tmp/current_media_art.png && icon=/tmp/current_media_art.png ;;
    file://*) icon=${art#file://} ;;
esac

# App name = the player, cut at the first dot like the bar's "via ..."
# (firefox.instance_1_3 -> firefox), so the popup reads TRANSMISSION · MPD.
notify-send -a "${PLAYER%%.*}" -t 2500 -i "$icon" \
    -h string:x-canonical-private-synchronous:media \
    "$title" "$body"
