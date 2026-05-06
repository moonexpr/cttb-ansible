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

set -u

USER="${PAM_USER:-}"
[[ -z "$USER" ]] && exit 0

# Resolve uid (numeric, for /run/sudhanix-tokens layout)
UID_NUM="$(id -u "$USER" 2>/dev/null || true)"
[[ -z "$UID_NUM" ]] && exit 0

DIR=/run/sudhanix-tokens
TOKEN="$DIR/${UID_NUM}.tok"

# Read the password (single line) from stdin
read -r PW
[[ -z "$PW" ]] && exit 0

# Ensure dir exists with safe perms (the tmpfiles.d entry should make it
# 1733 root:root, but be defensive in case it didn't run yet).
mkdir -p "$DIR" 2>/dev/null
chmod 1733 "$DIR" 2>/dev/null

# Write the token, owned by the user, readable only by them.
umask 077
printf '%s' "$PW" > "$TOKEN"
chown "$UID_NUM:$UID_NUM" "$TOKEN" 2>/dev/null
chmod 0600 "$TOKEN" 2>/dev/null

exit 0
