#!/bin/bash
# Called by pam_exec.so on session close to wipe the cached token.
#
# pam_exec invokes the script for BOTH pam_open_session and pam_close_session.
# Without the PAM_TYPE gate below, this script would shred the token at
# session-OPEN — immediately after the auth-phase cache-pam-token wrote it —
# leaving sudhanix-welcome with nothing to read. Gate to close_session only.
#
# Diagnostic logging mirrors cache-pam-token.sh; same /var/log file.

set -u

LOG=/var/log/sudhanix-pam-cache.log
log() {
    printf '[%s pid=%s shred] %s\n' "$(date '+%F %T')" "$$" "$*" >> "$LOG" 2>/dev/null
}

PAM_TYPE_VAL="${PAM_TYPE:-<unset>}"
USER="${PAM_USER:-}"
log "invoked PAM_TYPE=${PAM_TYPE_VAL} PAM_USER=${USER:-<empty>} PAM_SERVICE=${PAM_SERVICE:-<unset>}"

if [[ "$PAM_TYPE_VAL" != "close_session" ]]; then
    log "skip: not close_session"
    exit 0
fi

if [[ -z "$USER" ]]; then
    log "skip: empty PAM_USER"
    exit 0
fi

UID_NUM="$(id -u "$USER" 2>/dev/null || true)"
if [[ -z "$UID_NUM" ]]; then
    log "skip: id -u $USER produced no numeric uid"
    exit 0
fi

TOKEN="/run/sudhanix-tokens/${UID_NUM}.tok"
if [[ -f "$TOKEN" ]]; then
    if shred -uz "$TOKEN" 2>/dev/null; then
        log "shredded $TOKEN"
    else
        log "shred failed: $TOKEN"
    fi
else
    log "no token to shred at $TOKEN"
fi

exit 0
