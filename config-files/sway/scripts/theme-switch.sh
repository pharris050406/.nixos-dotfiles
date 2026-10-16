#!/bin/sh
# Theme switcher. Reads themes.conf and renders theme files for mako, sway,
# quickshell, rmpc and nvim. Run with no args for the wmenu picker, or pass
# a theme name to apply it directly.
#
# Usage: theme-switch.sh [name | --list | --current]

set -eu

CONF="${THEME_CONF:-$HOME/.config/themes.conf}"
MAKO_CONF="$HOME/.config/mako/config"
SWAY_THEME_CONF="$HOME/.config/sway/theme.conf"
QS_THEME_JSON="$HOME/.cache/theme-colors.json"
COLORS_ENV="$HOME/.cache/theme-colors.sh"
STATE_FILE="$HOME/.local/state/ndots-theme"
HISTORY_FILE="$HOME/.local/state/theme-history"
RMPC_TEMPLATE="$HOME/.config/rmpc/theme.ron.template"
RMPC_THEME="$HOME/.config/rmpc/themes/ndots.ron"
NVIM_THEME_LUA="$HOME/.cache/nvim/theme.lua"

# "#1a1b26" or "#801a1b26" -> "1a1b26"  (replaces the bash ${v: -6})
hex6() {
    v=${1#\#}
    [ ${#v} -eq 8 ] && v=${v#??}
    printf '%s' "$v"
}

load_theme() {
    line=$(awk -F'|' -v n="$1" '$1 == n { print; exit }' "$CONF")
    if [ -z "$line" ]; then
        echo "Unknown theme: $1" >&2
        echo "Available:" >&2
        awk -F'|' '!/^#/ && NF > 1 { print "  " $1 }' "$CONF" >&2
        exit 1
    fi
    # heredoc keeps read in the current shell (a pipe would subshell it)
    IFS='|' read -r THEME_NAME BACKGROUND BACKGROUND_PANEL FOREGROUND MUTED \
        ACCENT1 ACCENT2 ACCENT3 ACCENT4 ACCENT5 ACCENT6 ACCENT7 \
        FONT UI_FONT_SIZE BAR_FONT_SIZE BAR_COLOR BAR_OPACITY IS_LIGHT <<EOF
$line
EOF
}

render() {
    mkdir -p "${MAKO_CONF%/*}" "${SWAY_THEME_CONF%/*}" "${QS_THEME_JSON%/*}" \
             "${COLORS_ENV%/*}" "${STATE_FILE%/*}" "${HISTORY_FILE%/*}" \
             "${RMPC_THEME%/*}" "${NVIM_THEME_LUA%/*}"

    BG_HEX=$(hex6 "$BACKGROUND")
    FG_HEX=$(hex6 "$FOREGROUND")
    A2_HEX=$(hex6 "$ACCENT2")

cat > "$MAKO_CONF" <<EOF
font=$FONT $UI_FONT_SIZE
background-color=$BACKGROUND
text-color=$FOREGROUND
border-color=$FOREGROUND
border-size=2
default-timeout=5000

[urgency=high]
border-color=$ACCENT6
EOF

cat > "$SWAY_THEME_CONF" <<EOF
set \$thm_bg $BACKGROUND
set \$thm_fg $FOREGROUND
set \$thm_blue $ACCENT2

set \$menu wmenu-run -f "$FONT $UI_FONT_SIZE" -N "$BG_HEX" -n "$FG_HEX" -S "$FG_HEX" -s "$BG_HEX"
EOF

cat > "$QS_THEME_JSON" <<EOF
{
    "background": "$BACKGROUND_PANEL",
    "foreground": "$FOREGROUND",
    "muted": "$MUTED",
    "accent1": "$ACCENT1",
    "accent2": "$ACCENT2",
    "accent3": "$ACCENT3",
    "accent4": "$ACCENT4",
    "accent5": "$ACCENT5",
    "accent6": "$ACCENT6",
    "accent7": "$ACCENT7",
    "barColor": "$BAR_COLOR",
    "barOpacity": $BAR_OPACITY,
    "font": "$FONT",
    "fontSize": $BAR_FONT_SIZE
}
EOF

cat > "$COLORS_ENV" <<EOF
export THM_BG="$BG_HEX"
export THM_FG="$FG_HEX"
export THM_BLUE="$A2_HEX"
export THM_FONT="$FONT"
export THM_FONT_SIZE="$UI_FONT_SIZE"
EOF

cat > "$NVIM_THEME_LUA" <<EOF
return {
  name = "$THEME_NAME",
  bg = "$BACKGROUND",
  bg_panel = "$BACKGROUND_PANEL",
  fg = "$FOREGROUND",
  muted = "$MUTED",
  accent1 = "$ACCENT1",
  accent2 = "$ACCENT2",
  accent3 = "$ACCENT3",
  accent4 = "$ACCENT4",
  accent5 = "$ACCENT5",
  accent6 = "$ACCENT6",
  accent7 = "$ACCENT7",
  font = "$FONT",
  is_light = $IS_LIGHT,
}
EOF

    if [ -f "$RMPC_TEMPLATE" ] && command -v envsubst >/dev/null 2>&1; then
        THM_BG="#$(hex6 "$BACKGROUND")"
        THM_BG_PANEL="#$(hex6 "$BACKGROUND_PANEL")"
        THM_FG="#$(hex6 "$FOREGROUND")"
        THM_MUTED="#$(hex6 "$MUTED")"
        # accent -> named colour mapping carried over from the nix version;
        # only ACCENT2=blue is confirmed. Check against your rmpc template.
        THM_CYAN="#$(hex6 "$ACCENT1")"
        THM_BLUE="#$(hex6 "$ACCENT2")"
        THM_GREEN="#$(hex6 "$ACCENT3")"
        THM_YELLOW="#$(hex6 "$ACCENT4")"
        THM_ORANGE="#$(hex6 "$ACCENT5")"
        THM_RED="#$(hex6 "$ACCENT6")"
        THM_PURPLE="#$(hex6 "$ACCENT7")"
        export THM_BG THM_BG_PANEL THM_FG THM_MUTED THM_CYAN THM_BLUE \
               THM_GREEN THM_YELLOW THM_ORANGE THM_RED THM_PURPLE
        envsubst '$THM_BG $THM_BG_PANEL $THM_FG $THM_MUTED $THM_BLUE $THM_CYAN $THM_GREEN $THM_YELLOW $THM_ORANGE $THM_RED $THM_PURPLE' \
            < "$RMPC_TEMPLATE" > "$RMPC_THEME"
    fi

    printf '%s\n' "$THEME_NAME" > "$STATE_FILE"

    makoctl reload >/dev/null 2>&1 || true
    swaymsg reload >/dev/null 2>&1 || true
}

record_history() {
    mkdir -p "${HISTORY_FILE%/*}"
    if [ -f "$HISTORY_FILE" ]; then
        tmp=$(mktemp)
        { printf '%s\n' "$1"; grep -vxF "$1" "$HISTORY_FILE" || true; } > "$tmp"
        mv "$tmp" "$HISTORY_FILE"
    else
        printf '%s\n' "$1" > "$HISTORY_FILE"
    fi
}

# Most-recently-used first, then any themes never picked, in file order.
get_ordered_themes() {
    hist="$HISTORY_FILE"
    [ -f "$hist" ] || hist=/dev/null
    awk -F'|' '
        FILENAME == ARGV[1] {
            if ($0 !~ /^#/ && NF > 1) { order[++n] = $1; valid[$1] = 1 }
            next
        }
        ($0 in valid) && !seen[$0] { print; seen[$0] = 1 }
        END { for (i = 1; i <= n; i++) if (!seen[order[i]]) print order[i] }
    ' "$CONF" "$hist"
}

apply_theme() {
    load_theme "$1"
    record_history "$THEME_NAME"
    render
}

if [ ! -f "$CONF" ]; then
    echo "theme config not found: $CONF" >&2
    exit 1
fi

case "${1:-}" in
    --list)    get_ordered_themes; exit 0 ;;
    --current) cat "$STATE_FILE" 2>/dev/null || true; exit 0 ;;
esac

if [ $# -ge 1 ]; then
    apply_theme "$1"
else
    if [ -f "$COLORS_ENV" ]; then
        . "$COLORS_ENV"
    fi
    CHOICE=$(get_ordered_themes | wmenu -i \
        -f "${THM_FONT:-monospace} ${THM_FONT_SIZE:-10}" \
        -N "${THM_BG:-1a1b26}" \
        -n "${THM_FG:-c0caf5}" \
        -S "${THM_FG:-c0caf5}" \
        -s "${THM_BG:-1a1b26}" || true)
    if [ -n "$CHOICE" ]; then
        apply_theme "$CHOICE"
    fi
fi
