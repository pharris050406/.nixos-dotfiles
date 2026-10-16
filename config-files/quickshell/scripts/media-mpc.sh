#!/bin/sh
# Replacement for the MPRIS/playerctl media-source.sh, driven by mpc instead.
# FreeBSD + mpd has no MPRIS bus, so we poll mpc and emit the same protocol
# the widget already parses:
#   META|<Playing|Paused|Stopped>|<lengthMicroseconds>|<track>
#   POS|<positionSeconds>

MPD_HOST=${MPD_HOST:-127.0.0.1}
export MPD_HOST

to_secs() {
    # mm:ss or h:mm:ss -> seconds
    echo "$1" | awk -F: '{
        if (NF==3) print $1*3600 + $2*60 + $3;
        else if (NF==2) print $1*60 + $2;
        else print $1 + 0;
    }'
}

prev_meta=""

while :; do
    st=$(mpc status 2>/dev/null)

    case "$st" in
        *"[playing]"*) status=Playing ;;
        *"[paused]"*)  status=Paused ;;
        *)             status=Stopped ;;
    esac

    if [ "$status" = "Stopped" ]; then
        meta="META|Stopped|0|"
        [ "$meta" != "$prev_meta" ] && { printf '%s\n' "$meta"; prev_meta="$meta"; }
        sleep 1
        continue
    fi

    track=$(mpc -f '%artist% - %title%' current 2>/dev/null)
    [ -z "$track" ] && track=$(mpc current 2>/dev/null)
    [ -z "$track" ] && track="Unknown"

    # Grab the cur/tot field, e.g. "1:04/3:20", from the status line.
    times=$(printf '%s\n' "$st" | awk '{
        for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+:[0-9]+\/[0-9]+:[0-9]+/) { print $i; exit }
    }')
    cur=${times%%/*}
    tot=${times##*/}
    cursec=$(to_secs "${cur:-0:0}")
    totsec=$(to_secs "${tot:-0:0}")

    meta="META|$status|$(( totsec * 1000000 ))|$track"
    [ "$meta" != "$prev_meta" ] && { printf '%s\n' "$meta"; prev_meta="$meta"; }
    printf 'POS|%s\n' "${cursec:-0}"

    sleep 1
done
