#!/bin/bash
# Pick a random wallpaper from /usr/share/backgrounds/cttb/ and set it on
# every xfdesktop monitor for the current user. Runs via XDG autostart at
# XFCE session start so each login begins on a different wallpaper. The
# in-session backdrop-cycle-timer still rotates while the session is up;
# this script just randomizes the starting point.

set -e

WP_DIR="/usr/share/backgrounds/cttb"
[ -d "$WP_DIR" ] || exit 0

# Glob for images. Bail if there are none.
shopt -s nullglob
files=( "$WP_DIR"/*.{jpg,jpeg,png,JPG,JPEG,PNG} )
shopt -u nullglob
[ ${#files[@]} -gt 0 ] || exit 0

pick="${files[RANDOM % ${#files[@]}]}"

# Enumerate every monitor backdrop path xfconf knows about and set
# last-image. xfdesktop watches xfconf and updates the wallpaper live.
xfconf-query -c xfce4-desktop -l 2>/dev/null \
    | grep -E '/backdrop/screen[0-9]+/monitor.+/workspace[0-9]+/last-image$' \
    | while IFS= read -r prop; do
        xfconf-query -c xfce4-desktop -p "$prop" -s "$pick" 2>/dev/null || true
      done
