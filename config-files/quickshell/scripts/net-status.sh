#!/bin/sh
# Emits: IP|downBytesPerSec|upBytesPerSec   once per second.
# (Plain byte counts; Net.qml's Lib.parseRate reads them as-is.)
#
# Linux: the default route comes from /proc/net/route and the byte counters
# from /sys/class/net/<if>/statistics, both read with shell builtins, so a
# tick costs one process (the sleep). The address is looked up with `ip`
# when the interface changes and every 5 s after that.
# Stops as soon as nobody reads it (printf fails after a bar reload).

# Default route with the lowest metric -> IFC (empty when there isn't one).
# /proc/net/route columns: Iface Destination Gateway Flags RefCnt Use Metric Mask ...
default_iface() {
    IFC= _best=
    while read -r _if _dst _gw _fl _rc _use _met _mask _rest; do
        [ "$_dst" = 00000000 ] && [ "$_mask" = 00000000 ] || continue
        [ $(( 0x$_fl & 1 )) -eq 1 ] || continue          # RTF_UP
        if [ -z "$_best" ] || [ "$_met" -lt "$_best" ]; then
            _best=$_met IFC=$_if
        fi
    done < /proc/net/route
}

ipv4() {   # first IPv4 address on $1
    set -- $(ip -4 -o addr show dev "$1" 2>/dev/null)
    [ -n "$4" ] && printf '%s\n' "${4%%/*}"
}

IFACE= IP=0.0.0.0 n=0 r1= t1=
while :; do
    default_iface
    if [ "$IFC" != "$IFACE" ]; then
        IFACE=$IFC r1= n=0                  # different interface: restart the rate
    fi
    if [ -n "$IFACE" ] && [ "$n" -le 0 ]; then
        IP=$(ipv4 "$IFACE")
        [ -z "$IP" ] && IP=0.0.0.0
        n=5
    fi
    n=$((n - 1))

    if [ -z "$IFACE" ]; then
        printf '0.0.0.0|0|0\n' || exit 0
        sleep 2
        continue
    fi

    s=/sys/class/net/$IFACE/statistics
    r2=0 t2=0
    read -r r2 2>/dev/null < "$s/rx_bytes"
    read -r t2 2>/dev/null < "$s/tx_bytes"
    if [ -n "$r1" ]; then
        d=$((r2 - r1)) u=$((t2 - t1))
        [ "$d" -lt 0 ] && d=0
        [ "$u" -lt 0 ] && u=0
        printf '%s|%s|%s\n' "$IP" "$d" "$u" || exit 0
    fi
    r1=$r2 t1=$t2
    sleep 1
done
