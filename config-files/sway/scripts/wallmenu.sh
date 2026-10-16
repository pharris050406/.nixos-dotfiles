#!/bin/sh
# wallmenu.sh - pick a wallpaper from ~/Pictures/Wallpapers with wmenu

command -v wmenu  >/dev/null || { echo "wmenu not found"; exit 1; }
command -v swaybg >/dev/null || { echo "swaybg not found"; exit 1; }

dir="$HOME/Pictures/Wallpapers"
link="$HOME/.cache/wallpaper"
hist="$HOME/.cache/wmenu-wall-history"

# shellcheck source=/dev/null
[ -f "$HOME/.cache/theme-colors.sh" ] && . "$HOME/.cache/theme-colors.sh"

cd "$dir" || exit 1
touch "$hist" 2>/dev/null

# 1. current wallpapers
files=$(ls | grep -iE '\.(png|jpe?g)$')

# 2. prune history entries whose file is gone, keeping recency order
if [ -s "$hist" ]; then
    printf '%s\n' "$files" |
        awk 'NR == FNR { ok[$0]; next } $0 in ok' - "$hist" > "$hist.tmp"
    mv -f "$hist.tmp" "$hist"
fi

# 3. history first, then everything else, no duplicates
pick=$(
    { cat "$hist"; printf '%s\n' "$files"; } |
    awk 'NF && !seen[$0]++' |
    "$HOME/.config/quickshell/scripts/dfmenu" -i -p plates -f "${THM_FONT:-monospace} ${THM_FONT_SIZE:-10}" \
        -N "${THM_BG:-1a1b26}" -n "${THM_FG:-c0caf5}" \
        -S "${THM_FG:-c0caf5}" -s "${THM_BG:-1a1b26}"
) || exit 0

[ -n "$pick" ] || exit 0

# 4. move the pick to the top of history, cap at 20
{ printf '%s\n' "$pick"; grep -vxF -e "$pick" "$hist"; } | head -n 20 > "$hist.tmp"
mv -f "$hist.tmp" "$hist"

# already the current wallpaper? nothing else to do
[ "$(readlink "$link")" = "$dir/$pick" ] && exit 0

ln -sf "$dir/$pick" "$link"

# start the new swaybg before killing the old one, so there's no black gap
old=$(pgrep -x swaybg)
swaybg -i "$link" -m fill >/dev/null 2>&1 &
sleep 0.5
[ -n "$old" ] && kill $old
