#!/usr/bin/env bash
# gauges.sh — place 6 gauges in a centered, evenly spaced 2x3 grid (sway/SwayFX)
#
#   gauges.sh calibrate   pick: Gauge button, yoke, top-left gauge, bottom-row height
#   gauges.sh preview     hover each spot in order (no clicks) so you can check it
#   gauges.sh next        place the next gauge (bind this to a key)
#   gauges.sh reset       start over from gauge 1 (after "Remove gauges" in game)
#
# Needs: swaymsg (comes with sway), slurp (only for calibrate)
set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/gauge-macro.conf"
STATE="${XDG_RUNTIME_DIR:-/tmp}/gauge-macro.idx"
SEAT="${SEAT:-seat0}"
ROWS=2
COLS=3
TOTAL=$((ROWS * COLS))
DELAY="${DELAY:-0.30}"      # pause between switching gauge type and placing

notify() { echo "$1" >&2; command -v notify-send >/dev/null && notify-send -t 1500 "gauges" "$1" || true; }

pick() {
  notify "$1"
  slurp -p -f '%x %y'
  echo   # slurp's custom format has no trailing newline; read needs one
}

calibrate() {
  local BX BY CX _ X1 Y1 Y2 X2
  read -r BX BY < <(pick "1/4: click the 'Gauge: …' button")
  read -r CX _  < <(pick "2/4: click the yoke stick (sets the centre line)")
  read -r X1 Y1 < <(pick "3/4: click where the TOP-LEFT gauge goes")
  read -r _  Y2 < <(pick "4/4: click anywhere at the height of the BOTTOM row")
  X2=$((2 * CX - X1))   # mirror the left column across the yoke
  local keep=""
  [[ -f $CONF ]] && keep=$(grep '^SPACING=' "$CONF" || true)
  mkdir -p "$(dirname "$CONF")"
  printf 'BX=%s\nBY=%s\nX1=%s\nY1=%s\nX2=%s\nY2=%s\n' \
    "$BX" "$BY" "$X1" "$Y1" "$X2" "$Y2" > "$CONF"
  [[ -n $keep ]] && echo "$keep" >> "$CONF"
  rm -f "$STATE"
  echo "saved to $CONF:"; cat "$CONF"
}

load() {
  [[ -f $CONF ]] || { notify "no calibration yet, run: gauges.sh calibrate"; exit 1; }
  # shellcheck source=/dev/null
  source "$CONF"
}

sw() { swaymsg -q "seat $SEAT cursor $*"; }

hover() {
  sw set "$1" "$2"
  sleep 0.05
  sw move 1 0; sw move -1 0   # tiny wiggle so the game registers the hover
  sleep 0.08
}

click() {
  hover "$1" "$2"
  sw press button1
  sleep 0.06
  sw release button1
}

# spot <index 0..TOTAL-1>  ->  prints "x y"
spot() {
  local r=$(($1 / COLS)) c=$(($1 % COLS))
  awk -v x1="$X1" -v x2="$X2" -v y1="$Y1" -v y2="$Y2" -v s="${SPACING:-1}" \
      -v c="$c" -v r="$r" -v nc="$COLS" -v nr="$ROWS" \
      'BEGIN { cx = (x1 + x2) / 2; cy = (y1 + y2) / 2
               x = x1 + (x2 - x1) * c / (nc - 1)
               y = y1 + (y2 - y1) * r / (nr - 1)
               printf "%d %d", cx + (x - cx) * s + 0.5, cy + (y - cy) * s + 0.5 }'
}

preview() {
  load
  local i x y
  for s in 3 2 1; do echo "starting in $s…"; sleep 1; done
  for ((i = 0; i < TOTAL; i++)); do
    read -r x y < <(spot "$i"; echo)
    echo "gauge $((i + 1))/$TOTAL at $x,$y"
    hover "$x" "$y"; sleep 0.7
  done
}

next() {
  load
  exec 9>"$STATE.lock"
  flock -n 9 || exit 0          # ignore extra presses while one is running
  local i x y
  i=$(cat "$STATE" 2>/dev/null || echo 0)
  if ((i >= TOTAL)); then notify "all $TOTAL placed — 'reset' to start over"; exit 0; fi
  if ((i > 0)); then            # switch type now, after the mesh has settled
    click "$BX" "$BY"
    sleep "$DELAY"
  fi
  read -r x y < <(spot "$i"; echo)
  click "$x" "$y"
  echo $((i + 1)) > "$STATE"
  notify "placed gauge $((i + 1))/$TOTAL"
}

case "${1:-}" in
  calibrate) calibrate ;;
  preview)   preview ;;
  next)      next ;;
  reset)     rm -f "$STATE"; notify "reset — next press places gauge 1" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
