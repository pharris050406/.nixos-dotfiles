#!/bin/sh
# Hover details for the CPU and memory widgets.  Usage: top-procs.sh cpu|mem
# Prints KEY|value lines, plus PROC|amount|name for the top 3 processes.
# (Nothing in the bar calls this right now; it's kept working for when it does.)
# Note: Linux ps %cpu is the average over each process's whole life, not the
# last few seconds like FreeBSD's.
case "$1" in
cpu)
    read -r l1 l5 l15 _ < /proc/loadavg
    printf 'LOAD|%s %s %s\n' "$l1" "$l5" "$l15"
    # Package temperature: coretemp (Intel) / k10temp, zenpower (AMD), else the
    # x86_pkg_temp thermal zone. Silently skipped when none exist.
    t=
    for h in /sys/class/hwmon/hwmon*; do
        read -r name 2>/dev/null < "$h/name" || continue
        case $name in coretemp|k10temp|zenpower)
            read -r t 2>/dev/null < "$h/temp1_input" && break ;;
        esac
    done
    if [ -z "$t" ]; then
        for z in /sys/class/thermal/thermal_zone*; do
            read -r ty 2>/dev/null < "$z/type" || continue
            [ "$ty" = x86_pkg_temp ] && read -r t 2>/dev/null < "$z/temp" && break
        done
    fi
    [ -n "$t" ] && printf 'TEMP|%d.%dC\n' $((t / 1000)) $((t % 1000 / 100))
    ps -eo pcpu=,comm= --sort=-pcpu | head -n 3 \
        | awk '{c=$1; $1=""; sub(/^ +/, ""); printf "PROC|%s%%|%s\n", c, $0}'
    ;;
mem)
    awk '/^SwapTotal:/ {t = $2} /^SwapFree:/ {f = $2}
        END {if (t) printf "SWAP|%.2f of %.1f GiB\n", (t - f)/1048576, t/1048576}' /proc/meminfo
    # ZFS on Linux: the ARC counts as used memory, so show how much of it there is.
    [ -r /proc/spl/kstat/zfs/arcstats ] &&
        awk '$1 == "size" {printf "ARC|%.2f GiB\n", $3/1073741824}' /proc/spl/kstat/zfs/arcstats
    ps -eo rss=,comm= --sort=-rss | head -n 3 \
        | awk '{r=$1; $1=""; sub(/^ +/, ""); printf "PROC|%.0f MiB|%s\n", r/1024, $0}'
    ;;
esac
