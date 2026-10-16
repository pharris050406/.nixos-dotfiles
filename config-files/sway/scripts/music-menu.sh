#!/usr/bin/env bash
 
command -v wmenu >/dev/null || { echo "wmenu not found"; exit 1; }
command -v mpc >/dev/null || { echo "mpc not found"; exit 1; }
 
COLORS_ENV="$HOME/.cache/theme-colors.sh"
# shellcheck source=/dev/null
[ -f "$COLORS_ENV" ] && . "$COLORS_ENV"
 
HISTFILE="$HOME/.cache/wmenu-music-history"
touch "$HISTFILE" 2>/dev/null
 
# Wake media-source.sh out of its `sleep 1` so the widget refreshes immediately.
# Same trick media-ctl.sh uses: kill the sleep child of the polling loop.
nudge_widget() {
  local src_pid
  src_pid=$(pgrep -f 'media-source\.sh' | head -n1)
  [ -n "$src_pid" ] && pkill -P "$src_pid" sleep 2>/dev/null
  return 0
}

# Position of a URI in the current queue, empty if not queued.
queue_pos() {
  mpc playlist -f '%position%\t%file%' 2>/dev/null \
    | awk -F'\t' -v u="$1" '$2 == u { print $1; exit }'
}
 
# Optional: point the widget's pinned player at MPD, since the menu is
# explicitly starting MPD playback. Uncomment the call below to enable.
# focus_mpd() {
#   local state_file="$HOME/.cache/quickshell/selected-player"
#   local mpd_player
#   mpd_player=$(playerctl -l 2>/dev/null | grep -m1 '^mpd')
#   [ -n "$mpd_player" ] && printf '%s\n' "$mpd_player" > "$state_file"
#   return 0
# }
 
# 1. Fetch current MPD items
CURRENT_ITEMS=$(
  {
    mpc lsplaylists | sed 's/^/Playlist: /'
    mpc list album | grep '\S' | sed 's/^/Album: /'
    mpc listall | awk -F/ '{
      fname = $NF
      sub(/\.[^.]+$/, "", fname)
      artist = (NF >= 2) ? $1 : ""
      if (artist != "") {
        print "Track: " fname " - " artist
      } else {
        print "Track: " fname
      }
    }'
  }
)
 
# 2. Prune dead entries from HISTFILE, PRESERVING recency order.
#    History is the input, the library is the pattern list — so output
#    order follows HISTFILE (newest first), not MPD's listing order.
if [ -s "$HISTFILE" ]; then
  grep -F -x -f <(printf '%s\n' "$CURRENT_ITEMS") "$HISTFILE" > "$HISTFILE.tmp" 2>/dev/null
  mv -f "$HISTFILE.tmp" "$HISTFILE"
fi
 
# 3. Combine valid history + current MPD items
SELECTION=$(
  {
    cat "$HISTFILE"
    echo "$CURRENT_ITEMS"
  } | awk 'NF && !seen[$0]++' | "$HOME/.config/quickshell/scripts/dfmenu" -i -p transmissions -f "${THM_FONT:-monospace} ${THM_FONT_SIZE:-10}" \
      -N "${THM_BG:-1a1b26}" -n "${THM_FG:-c0caf5}" \
      -S "${THM_FG:-c0caf5}" -s "${THM_BG:-1a1b26}"
)
 
[ -z "$SELECTION" ] && exit 0
 
grep -v -F -x "$SELECTION" "$HISTFILE" > "$HISTFILE.tmp" 2>/dev/null
echo "$SELECTION" | cat - "$HISTFILE.tmp" | head -n 20 > "$HISTFILE"
rm -f "$HISTFILE.tmp"
 
PLAYED=0
 
if [[ "$SELECTION" == Playlist:* ]]; then
  NAME="${SELECTION#Playlist: }"
  mpc clear
  mpc load "$NAME"
  mpc play
  PLAYED=1
 
elif [[ "$SELECTION" == Album:* ]]; then
  NAME="${SELECTION#Album: }"
  mpc clear
  mpc findadd album "$NAME"
  mpc play
  PLAYED=1
 
elif [[ "$SELECTION" == Track:* ]]; then
  NAME="${SELECTION#Track: }"
  URI=$(mpc listall | awk -F/ -v sel="$NAME" '{
    fname = $NF
    sub(/\.[^.]+$/, "", fname)
    artist = (NF >= 2) ? $1 : ""
    display = (artist != "") ? fname " - " artist : fname
    if (display == sel) {
      print $0
      exit
    }
  }')
 
  if [ -n "$URI" ]; then
    # Already queued? Jump to it. Otherwise append and jump to the end,
    # so the existing queue survives instead of being wiped.
    POS=$(queue_pos "$URI")
    if [ -n "$POS" ]; then
      mpc play "$POS"
    else
      mpc add "$URI"
      mpc play "$(mpc playlist | wc -l)"
    fi
    PLAYED=1
  fi
fi
 
if [ "$PLAYED" -eq 1 ]; then
  # focus_mpd
 
  # Wait (max ~1s) until MPD actually reports playing, otherwise the widget
  # polls before MPRIS has published the new track and shows stale metadata.
  for _ in $(seq 1 20); do
    mpc status 2>/dev/null | grep -q '^\[playing\]' && break
    sleep 0.05
  done
  sleep 0.05
 
  nudge_widget
  # Insurance in case MPRIS lagged behind mpd's own status
  ( sleep 0.6; nudge_widget ) >/dev/null 2>&1 &
fi
