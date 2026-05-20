#!/bin/bash
# sudhanix-session-watchdog — monitors xfwm4 and ends the session cleanly on crash.
# Runs from /etc/xdg/autostart/ at graphical session start, as the logged-in user.
#
# Lifecycle:
#   1. Wait up to 30 s for xfwm4 to appear after session launch.
#      If absent: attempt one direct launch, then recover if still missing.
#   2. Track its PID. On disappearance, wait RECOVERY_HOLD seconds for --replace.
#   3. If still gone: collect diagnostics, show zenity, call xfce4-session-logout.

set -u

LOG="/tmp/sudhanix-watchdog-$(id -un)-$(date +%Y%m%d-%H%M%S).log"
RECOVERY_HOLD=5

log() { echo "$(date -Iseconds) $*" >> "$LOG"; }

log "watchdog started pid=$$ user=$(id -un) display=${DISPLAY:-unset}"

recover() {
    local reason="$1"
    log "$reason — collecting diagnostics"

    REPORT_DIR="/tmp/sudhanix-crash-$(hostname -s)-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$REPORT_DIR"

    {
        echo "=== META ==="
        echo "user=$(id -un) uid=$(id -u)"
        echo "hostname=$(hostname -f)"
        echo "kernel=$(uname -r)"
        echo "os=$(lsb_release -ds 2>/dev/null)"
        echo "reason=$reason"
        echo "recovery=$(date -Iseconds)"
    } > "$REPORT_DIR/meta.txt"

    tail -200 "${HOME}/.xsession-errors" > "$REPORT_DIR/xsession-errors.txt" 2>/dev/null

    journalctl --user-unit=xfce4-session.service -n 100 --no-pager \
        > "$REPORT_DIR/journal.txt" 2>/dev/null || \
        journalctl -n 100 --no-pager 2>/dev/null | grep -i "xfwm4\|xfce4-session" \
        > "$REPORT_DIR/journal.txt"

    xfconf-query -c xfwm4 -lv > "$REPORT_DIR/xfwm4-config.txt" 2>/dev/null

    ps aux > "$REPORT_DIR/process-list.txt" 2>/dev/null

    ls /var/lib/systemd/coredump/*.xfwm4.* > "$REPORT_DIR/coredumps.txt" 2>/dev/null \
        || echo "no xfwm4 coredumps in /var/lib/systemd/coredump/" > "$REPORT_DIR/coredumps.txt"

    tar czf "${REPORT_DIR}.tar.gz" -C "$(dirname "$REPORT_DIR")" \
        "$(basename "$REPORT_DIR")" 2>/dev/null
    rm -rf "$REPORT_DIR"

    log "report saved: ${REPORT_DIR}.tar.gz"
    # Storehouse upload deferred until crash-report dropzone is provisioned.
    # When ready: scp "${REPORT_DIR}.tar.gz" \
    #     administrator@storehouse.cttb:/srv/storehouse/crash-reports/$(hostname -s)/

    # User-visible message before logout — block until dialog closes or times out.
    if command -v zenity >/dev/null 2>&1; then
        zenity --info \
            --title="Sudhanix" \
            --text="Session ended due to a display-server error.\nLogging in again should restore your work." \
            --timeout=10 2>/dev/null
    fi

    log "requesting logout via xfce4-session-logout"
    xfce4-session-logout --logout --fast 2>/dev/null
    exit 0
}

# Wait for xfwm4 to appear (it may launch fractionally after autostart).
WM_PID=""
for _ in $(seq 1 30); do
    WM_PID=$(pgrep -x xfwm4 2>/dev/null | head -1)
    [ -n "$WM_PID" ] && break
    sleep 1
done

if [ -z "$WM_PID" ]; then
    log "xfwm4 never appeared within 30 s — attempting direct launch"
    xfwm4 --display "${DISPLAY:-:0}" &
    sleep 5
    WM_PID=$(pgrep -x xfwm4 2>/dev/null | head -1)
    if [ -n "$WM_PID" ]; then
        log "xfwm4 recovered via direct launch, pid=$WM_PID"
    else
        recover "xfwm4 never started (direct launch also failed)"
    fi
fi

log "tracking xfwm4 pid=$WM_PID"

# Watch loop — poll every 2 s while the process exists.
while [ -e "/proc/$WM_PID" ]; do
    sleep 2
done

log "xfwm4 pid=$WM_PID vanished — waiting ${RECOVERY_HOLD}s for --replace"
sleep "$RECOVERY_HOLD"

NEW_PID=$(pgrep -x xfwm4 2>/dev/null | head -1)
if [ -n "$NEW_PID" ]; then
    log "xfwm4 respawned as pid=$NEW_PID (--replace or restart) — re-arming"
    exec "$0"
fi

recover "xfwm4 pid=$WM_PID confirmed dead"
