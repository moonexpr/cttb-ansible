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

# Create-and-configure the backdrop for every *connected* output. The
# system-wide xfconf seed can only guess connector names (HDMI-1, DP-1, …);
# on hardware whose real connector isn't seeded, xfdesktop invents the
# property tree with stock defaults — folder /usr/share/backgrounds/xfce —
# which is exactly the reset this script exists to prevent. --create makes
# this correct on both first login (props absent) and every later one.
for out in $(xrandr --query 2>/dev/null | awk '/ connected/{print $1}'); do
    base="/backdrop/screen0/monitor${out}/workspace0"
    xfconf-query -c xfce4-desktop -p "$base/last-image" --create -t string -s "$pick" 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "$base/image-style" --create -t int -s 5 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "$base/backdrop-cycle-enable" --create -t bool -s true 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "$base/backdrop-cycle-random-order" --create -t bool -s true 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "$base/backdrop-cycle-period" --create -t uint -s 1 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "$base/backdrop-cycle-timer" --create -t uint -s 360 2>/dev/null || true
done

# Belt-and-braces: also refresh last-image on every backdrop path xfconf
# already knows about (covers monitor names xrandr and xfdesktop disagree on).
xfconf-query -c xfce4-desktop -l 2>/dev/null \
    | grep -E '/backdrop/screen[0-9]+/monitor.+/workspace[0-9]+/last-image$' \
    | while IFS= read -r prop; do
        xfconf-query -c xfce4-desktop -p "$prop" -s "$pick" 2>/dev/null || true
      done
