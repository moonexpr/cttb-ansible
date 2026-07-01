#!/usr/bin/env bash
# Print the Ansible vault password for cttb-ansible.
# Used as `ansible-vault --vault-password-file` argument (by cttb-vault.sh).
#
# Source order:
#   1. macOS Keychain entry CTTB_VAULT_PASS (primary; `security` CLI)
#   2. $CTTB_VAULT_PASS env var (fallback; Linux sysadmins without a Keychain —
#      set it in .claude/.env, see .claude/.env.example)
# Fails closed (exit 2) if neither is available.

set -euo pipefail

if command -v security >/dev/null 2>&1; then
    pw="$(security find-generic-password -s CTTB_VAULT_PASS -w 2>/dev/null || true)"
    if [[ -n "$pw" ]]; then
        printf '%s\n' "$pw"
        exit 0
    fi
fi

if [[ -n "${CTTB_VAULT_PASS:-}" ]]; then
    printf '%s\n' "$CTTB_VAULT_PASS"
    exit 0
fi

echo "error: CTTB_VAULT_PASS not found in macOS Keychain or env." >&2
echo "       Store it in Keychain:  security add-generic-password -s CTTB_VAULT_PASS -w" >&2
echo "       Or set it in .claude/.env (see .claude/.env.example)." >&2
exit 2