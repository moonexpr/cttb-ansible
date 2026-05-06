#!/bin/bash
# Called by pam_exec.so on session close to wipe the cached token.

USER="${PAM_USER:-}"
[[ -z "$USER" ]] && exit 0
UID_NUM="$(id -u "$USER" 2>/dev/null || true)"
[[ -z "$UID_NUM" ]] && exit 0

TOKEN="/run/sudhanix-tokens/${UID_NUM}.tok"
[[ -f "$TOKEN" ]] && shred -uz "$TOKEN" 2>/dev/null

exit 0
