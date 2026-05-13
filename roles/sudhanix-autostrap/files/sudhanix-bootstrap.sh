#!/bin/bash
#
# /usr/local/sbin/sudhanix-bootstrap — the second-stage autoinstaller body.
#
# Written to disk by cloud-init at PXE-install time (see
# roles/netinstall-2404/templates/autoinstall/user-data-desktop-minimal.j2),
# invoked exactly once by sudhanix-bootstrap.service.
#
# Pulls the cttb-ansible repo tarball from storehouse.cttb, extracts it into
# /var/lib/sudhanix/cttb-ansible/, apt-installs ansible-core, then runs
# build-sudhanix-autobootstrap.yml against localhost. The play's post_tasks
# touches /var/lib/sudhanix/bootstrap.done on success, which makes
# ConditionPathExists in the systemd unit skip re-runs.
#
# Exit codes propagate to systemd; non-zero -> Restart=on-failure path.

set -euo pipefail

# ── config ──────────────────────────────────────────────────────────────────
TARBALL_URL="http://storehouse.cttb/ansible/sudhanix-bootstrap-26.tar.gz"
WORK_DIR="/var/lib/sudhanix"
REPO_DIR="${WORK_DIR}/cttb-ansible"
DONE_FLAG="${WORK_DIR}/bootstrap.done"
LOG_TAG="sudhanix-bootstrap"

# ── helpers ─────────────────────────────────────────────────────────────────
log()  { logger -t "${LOG_TAG}" --stderr -- "$*"; }
die()  { log "FATAL: $*"; exit 1; }

# ── early exit if already done ─────────────────────────────────────────────
# Mirror the systemd Condition for the case where this script is invoked
# directly (not via the unit). Idempotent.
[[ -f "${DONE_FLAG}" ]] && { log "already complete (flag present); nothing to do"; exit 0; }

# ── 1. apt-install ansible-core ────────────────────────────────────────────
# We come up on a desktop-minimal install that has python3 but no ansible.
# The lab apt mirror (apt.cttb) carries ansible in noble universe.
log "stage 1/4: apt-install ansible-core"
export DEBIAN_FRONTEND=noninteractive
apt-get update -o Acquire::Retries=3 -qq
apt-get install -y --no-install-recommends \
    ansible-core ca-certificates curl rsync git \
    || die "apt-install of ansible-core failed"

# ── 2. fetch repo tarball ──────────────────────────────────────────────────
log "stage 2/4: fetch ${TARBALL_URL}"
mkdir -p "${WORK_DIR}"
TMP_TAR="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "${TMP_TAR}"' EXIT
curl --retry 3 --retry-delay 5 --connect-timeout 10 --max-time 600 \
     --fail --location --silent --show-error \
     --output "${TMP_TAR}" \
     "${TARBALL_URL}" \
    || die "tarball fetch failed (storehouse unreachable or 404)"

# Sanity-check size — a sub-1 KiB result is almost certainly an h5ai HTML
# index page that managed to 200, not the actual tarball.
TAR_SIZE="$(stat -c%s "${TMP_TAR}")"
[[ "${TAR_SIZE}" -gt 102400 ]] || die "tarball implausibly small (${TAR_SIZE} bytes) — wrong URL?"

# ── 3. extract over WORK_DIR ───────────────────────────────────────────────
log "stage 3/4: extract tarball into ${REPO_DIR}"
rm -rf "${REPO_DIR}"
mkdir -p "${REPO_DIR}"
tar -xzf "${TMP_TAR}" -C "${REPO_DIR}" --strip-components=1 \
    || die "tarball extraction failed"

# ── 4. run the play ────────────────────────────────────────────────────────
log "stage 4/4: ansible-playbook build-sudhanix-autobootstrap.yml"
cd "${REPO_DIR}"
ANSIBLE_HOST_KEY_CHECKING=False \
ANSIBLE_FORCE_COLOR=False \
    ansible-playbook -i localhost, --connection=local \
        plays/build-sudhanix-autobootstrap.yml \
        2>&1 | logger -t "${LOG_TAG}-play" --stderr \
    || die "ansible-playbook exited non-zero"

# ── done ───────────────────────────────────────────────────────────────────
# The play's post_tasks should have touched DONE_FLAG already. Defensive
# touch in case the play succeeded but the post_tasks block was skipped.
mkdir -p "${WORK_DIR}"
touch "${DONE_FLAG}"
log "bootstrap complete — flag set at ${DONE_FLAG}"
