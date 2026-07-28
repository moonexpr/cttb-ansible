#!/usr/bin/env bash
# cttb-deploy / scripts/deploy.sh
#
# Single-host, tag-scoped Ansible deploy via sudhanix26-rollout-stage2.yml.
# Run by /cttb-deploy (SKILL.md). Refuses fleet-wide invocation.

set -euo pipefail

ALIAS="${1:-}"
TAGS="${2:-}"
CHECK="${3:-}"

fail() { echo "[cttb-deploy] ERROR: $*" >&2; exit 2; }

[ -n "$ALIAS" ] || fail "missing alias (arg 1)"
[ -n "$TAGS" ]  || fail "missing tags (arg 2) — refuse to run tagless against a host"
case "$ALIAS" in
  all|"@*"|*,*) fail "fleet-wide deploys are not in scope for this skill ($ALIAS); use plays/sudhanix26-rollout.yml directly" ;;
esac

VAULT_HELPER=".claude/sysadmin/vault-pass"
[ -x "$VAULT_HELPER" ] || fail "$VAULT_HELPER not found or not executable"

# No --vault-password-file here: ansible.cfg sets vault_password_file globally.
# ansible_become_pass is supplied non-interactively so the deploy does not
# block on a prompt.
ARGS=(
  ansible-playbook
  -i inventory/hosts
  plays/sudhanix26-rollout-stage2.yml
  --limit "$ALIAS"
  --tags "$TAGS"
  --skip-tags zoom
  --diff
  -e "ansible_become_pass=$($VAULT_HELPER)"
)

if [ "$CHECK" = "--check" ]; then
  ARGS+=(--check)
  echo "[cttb-deploy] dry-run: $ALIAS / $TAGS" >&2
else
  echo "[cttb-deploy] deploy: $ALIAS / $TAGS" >&2
fi

exec "${ARGS[@]}"
