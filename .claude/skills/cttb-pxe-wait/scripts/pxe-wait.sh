#!/usr/bin/env bash
# cttb-pxe-wait / scripts/pxe-wait.sh
#
# Wait for a host to complete a PXE-install cycle (already in progress).
# Three phases: wait-for-down, sleep, wait-for-up, verify SSH.
# Agent-only — humans use plays/sudhanix26-rollout.yml.

set -euo pipefail

ALIAS="${1:-}"
SKIP_DOWN="${2:-}"

DOWN_TIMEOUT="${PXE_DOWN_TIMEOUT:-600}"
INSTALL_TIMEOUT="${PXE_INSTALL_TIMEOUT:-3600}"
PROBE_DELAY="${PXE_PROBE_DELAY:-120}"

fail() { echo "[cttb-pxe-wait] ERROR: $*" >&2; exit 2; }

[ -n "$ALIAS" ] || fail "missing alias (arg 1)"

# Resolve a connect-target: try the alias verbatim, then alias.cttb, then bail.
HOST="$ALIAS"
if ! getent hosts "$HOST" >/dev/null 2>&1 && ! ssh -G "$HOST" 2>/dev/null | grep -q '^hostname '; then
  HOST="${ALIAS}.cttb"
fi

wait_port() {
  local mode="$1" timeout="$2"   # mode: down|up
  local start=$SECONDS deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if nc -z -G 5 "$HOST" 22 2>/dev/null; then
      [ "$mode" = up ]   && return 0
    else
      [ "$mode" = down ] && return 0
    fi
    sleep 5
  done
  return 1
}

if [ "$SKIP_DOWN" != "--skip-down" ]; then
  echo "[cttb-pxe-wait] phase 1: waiting for $HOST to drop off (timeout ${DOWN_TIMEOUT}s)" >&2
  wait_port down "$DOWN_TIMEOUT" || fail "phase 1 timed out — $HOST did not go down"
fi

echo "[cttb-pxe-wait] phase 2: probe delay ${PROBE_DELAY}s (autoinstall in flight)" >&2
sleep "$PROBE_DELAY"

echo "[cttb-pxe-wait] phase 3: waiting for $HOST to return (timeout ${INSTALL_TIMEOUT}s)" >&2
wait_port up "$INSTALL_TIMEOUT" || fail "phase 3 timed out — $HOST did not return"

echo "[cttb-pxe-wait] phase 4: verify SSH on $HOST" >&2
HOSTNAME_OUT="$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$HOST" hostname 2>&1)" \
  || fail "phase 4 failed — SSH did not answer on $HOST: $HOSTNAME_OUT"

echo "[cttb-pxe-wait] $ALIAS back up: $HOSTNAME_OUT" >&2
