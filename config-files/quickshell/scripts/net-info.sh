#!/bin/sh
# Link details for the network widget. Prints:
#   iface|gateway|ssid|rx_total_bytes|tx_total_bytes|ping_ms
# Empty iface = no default route (offline). ping_ms = -1 on timeout.
#
# Kept cheap for battery: every 2s it only checks whether the route changed,
# by reading /proc/net/route with shell builtins (no processes). The full
# refresh -- Wi-Fi name, totals, one ping -- runs every 10s, or right away when
# the connection changes. Pinging less often also lets the Wi-Fi radio
# power-save between packets.
# Override the ping target with PING_HOST.
PING_HOST=${PING_HOST:-1.1.1.1}
TICK=2      # seconds between route checks
FULL=5      # full refresh every FULL ticks (10s)

# Lowest-metric default route -> "iface|gateway" (both empty when offline).
# Gateways in /proc/net/route are little-endian hex: 0101A8C0 = 192.168.1.1.
route_now() {
    _ifc= _gwx= _best=
    while read -r _if _dst _gw _fl _rc _use _met _mask _rest; do
        [ "$_dst" = 00000000 ] && [ "$_mask" = 00000000 ] || continue
        [ $(( 0x$_fl & 1 )) -eq 1 ] || continue          # RTF_UP
        if [ -z "$_best" ] || [ "$_met" -lt "$_best" ]; then
            _best=$_met _ifc=$_if _gwx=$_gw
        fi
    done < /proc/net/route
    _gwd=
    if [ -n "$_gwx" ] && [ "$_gwx" != 00000000 ]; then
        _x=$(( 0x$_gwx ))
        _gwd=$(( _x & 255 )).$(( (_x >> 8) & 255 )).$(( (_x >> 16) & 255 )).$(( (_x >> 24) & 255 ))
    fi
    R="$_ifc|$_gwd"
}

# SSID: ask NetworkManager (from its cached scan: --rescan no, or nmcli would
# trigger a fresh scan every time), else iw if it's installed.
# Wired interfaces have no /sys/class/net/<if>/wireless.
ssid_of() {
    [ -d "/sys/class/net/$1/wireless" ] || return 0
    _s=$(LC_ALL=C.UTF-8 timeout 2 nmcli -e no -t -f ACTIVE,SSID device wifi list ifname "$1" --rescan no 2>/dev/null |
        sed -n 's/^yes://p' | head -n 1)
    if [ -z "$_s" ] && command -v iw >/dev/null 2>&1; then
        _s=$(timeout 2 iw dev "$1" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p')
    fi
    printf '%s\n' "$_s"
}

last= n=0
while :; do
    route_now
    if [ "$R" != "$last" ] || [ "$n" -le 0 ]; then
        last=$R n=$FULL
        ifc=${R%%|*} gw=${R#*|}
        ssid= rx=0 tx=0 ms=-1
        if [ -n "$ifc" ]; then
            ssid=$(ssid_of "$ifc")
            read -r rx 2>/dev/null < "/sys/class/net/$ifc/statistics/rx_bytes"
            read -r tx 2>/dev/null < "/sys/class/net/$ifc/statistics/tx_bytes"
            # iputils: -W is the reply timeout in seconds (-t would be the TTL here)
            ms=$(ping -n -c 1 -W 1 "$PING_HOST" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p')
            ms=${ms:--1}
        fi
        printf '%s|%s|%s|%s|%s|%s\n' "$ifc" "$gw" "$ssid" "${rx:-0}" "${tx:-0}" "$ms" || exit 0   # bar reloaded: stop
    fi
    n=$((n - 1))
    sleep "$TICK"
done
