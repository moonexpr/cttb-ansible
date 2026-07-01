#!/usr/bin/env bash
# Wrapper around ansible-vault that pulls the password from macOS Keychain.
#
# Reads CTTB_VAULT_PASS via .claude/sysadmin/vault-pass.sh.
#
# Usage:
#   cttb-vault.sh edit <file>
#   cttb-vault.sh view <file>
#   cttb-vault.sh encrypt <file>
#   cttb-vault.sh decrypt <file>
#   cttb-vault.sh rekey <file>          # re-encrypt with current Keychain password
#   cttb-vault.sh <any other ansible-vault subcommand+args>

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
pass_file="$here/vault-pass.sh"

if [[ ! -x "$pass_file" ]]; then
    echo "error: $pass_file not executable" >&2
    exit 1
fi

exec ansible-vault "$@" --vault-password-file "$pass_file"
