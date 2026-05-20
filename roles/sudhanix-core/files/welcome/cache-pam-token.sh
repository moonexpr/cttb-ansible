#!/bin/bash
# Called by pam_exec.so during the auth phase with expose_authtok=1.
# Stdin = the cleartext password the user just typed.
# $PAM_USER = the username being authenticated.
#
# Caches the password into a tmpfs file owned by the user, mode 0600.
# The file lives only as long as /run is mounted (lost on reboot).
# pam_exec_session_close.sh shreds it when the session ends.
#
# We only run this for LOCAL authentications (graphical login). Remote SSH
# logins should NOT cache the password — see the PAM config that gates this
# with `pam_succeed_if.so service = lightdm` (or similar).
#
# Diagnostic logging: every branch logs to /var/log/sudhanix-pam-cache.log.
# Token CONTENTS are never logged — only its byte length on success.

set -u

LOG=/var/log/sudhanix-pam-cache.log
log() {
    printf '[%s pid=%s] %s\n' "$(date '+%F %T')" "$$" "$*" >> "$LOG" 2>/dev/null
}

USER="${PAM_USER:-}"
log "invoked PAM_USER=${USER:-<empty>} PAM_TYPE=${PAM_TYPE:-<unset>} PAM_SERVICE=${PAM_SERVICE:-<unset>}"

if [[ -z "$USER" ]]; then
    log "exit: empty PAM_USER"
    exit 0
fi

# Resolve uid (numeric, for /run/sudhanix-tokens layout)
UID_NUM="$(id -u "$USER" 2>/dev/null || true)"
if [[ -z "$UID_NUM" ]]; then
    log "exit: id -u $USER produced no numeric uid"
    exit 0
fi

DIR=/run/sudhanix-tokens
TOKEN="$DIR/${UID_NUM}.tok"

# Read the password (single line) from stdin.
# expose_authtok pipes PAM_AUTHTOK as the first stdin line.
read -r PW || true
if [[ -z "$PW" ]]; then
    log "exit: empty stdin (expose_authtok did not deliver token)"
    exit 0
fi

# Ensure dir exists with safe perms (the tmpfiles.d entry should make it
# 1733 root:root, but be defensive in case it didn't run yet).
if ! mkdir -p "$DIR" 2>/dev/null; then
    log "exit: mkdir $DIR failed"
    exit 0
fi
chmod 1733 "$DIR" 2>/dev/null || true

# Write atomically: mktemp(1) the file root-owned, populate, chown, fsync-rename.
# Avoids the EACCES path where bash > redirect tries to truncate a pre-existing
# user-owned token file. lightdm's pam_exec child has been observed unable to
# truncate-open the existing file (suspected AppArmor/seccomp mediation),
# even though it can create+rename a fresh one.
umask 077
TMP="$(mktemp -p "$DIR" ".${UID_NUM}.tok.XXXXXX" 2>/dev/null || true)"
if [[ -z "$TMP" ]]; then
    log "exit: mktemp in $DIR failed"
    exit 0
fi
chmod 0600 "$TMP" 2>/dev/null || true
if ! printf '%s' "$PW" > "$TMP"; then
    log "exit: write $TMP failed"
    rm -f "$TMP" 2>/dev/null
    exit 0
fi
chown "$UID_NUM:$UID_NUM" "$TMP" 2>/dev/null || log "warn: chown $TMP failed"
if mv -f "$TMP" "$TOKEN" 2>/dev/null; then
    log "wrote $TOKEN (${#PW} bytes)"
else
    log "exit: rename $TMP -> $TOKEN failed"
    rm -f "$TMP" 2>/dev/null
fi

exit 0
