#!/bin/bash
#
# /usr/local/sbin/sudhanix-bootstrap — the second-stage autoinstaller body.
#
# Written to disk by cloud-init at PXE-install time (see
# roles/netinstall-2404/templates/autoinstall/user-data-desktop-minimal.j2),
# invoked exactly once by sudhanix-bootstrap.service.
#
# Stages:
#   1. apt-install the bootstrap toolbelt (ansible-core, curl, …).
#   2. fetch the cttb-ansible tarball + sha256 sidecar from storehouse.cttb,
#      verify the checksum (refuse stale/tampered downloads).
#   3. extract into /var/lib/sudhanix/cttb-ansible/.
#   4. ONE bulk `apt install` of every host-agnostic package, then ONE bulk
#      `apt remove --purge` of the lubuntu-base cruft. Replaces dozens of
#      per-task apt calls the role chain would otherwise issue.
#   5. run build-sudhanix-autobootstrap.yml — the role's apt tasks are then
#      idempotent no-ops; only config work runs.
#
# The play's post_tasks touches /var/lib/sudhanix/bootstrap.done on success,
# which makes ConditionPathExists in the systemd unit skip re-runs.
#
# Exit codes propagate to systemd; non-zero -> Restart=on-failure path.

set -euo pipefail

# ── config ──────────────────────────────────────────────────────────────────
STOREHOUSE_BASE="http://storehouse.cttb/ansible"
TARBALL_NAME="sudhanix-bootstrap-26.tar.gz"
TARBALL_URL="${STOREHOUSE_BASE}/${TARBALL_NAME}"
SHA256_URL="${TARBALL_URL}.sha256"
WORK_DIR="/var/lib/sudhanix"
REPO_DIR="${WORK_DIR}/cttb-ansible"
DONE_FLAG="${WORK_DIR}/bootstrap.done"
LOG_TAG="sudhanix-bootstrap"

# Package list locations relative to the extracted REPO_DIR. The lists are
# regenerated from the role tree by plays/build-sudhanix-bootstrap-tarball.yml
# on every tarball build, so they never drift from the actual roles.
PKG_INSTALL_LIST="roles/sudhanix-autostrap/files/sudhanix-packages.txt"
PKG_REMOVE_LIST="roles/sudhanix-autostrap/files/sudhanix-packages-remove.txt"

# ── helpers ─────────────────────────────────────────────────────────────────
log()  { logger -t "${LOG_TAG}" --stderr -- "$*"; }
die()  { log "FATAL: $*"; exit 1; }

# Read a package-list file: strip comments + blank lines, output one name
# per line, suitable for piping into `xargs apt-get install`.
read_pkg_list() {
    local f="$1"
    [[ -f "$f" ]] || { log "package list missing: $f"; return 1; }
    grep -E '^[a-zA-Z0-9]' "$f" || true   # `|| true` so empty list isn't fatal
}

# ── early exit if already done ─────────────────────────────────────────────
# Mirror the systemd Condition for the case where this script is invoked
# directly (not via the unit). Idempotent.
[[ -f "${DONE_FLAG}" ]] && { log "already complete (flag present); nothing to do"; exit 0; }

# ── 1. apt-install the bootstrap toolbelt ───────────────────────────────────
# Desktop-minimal install has python3 + apt + curl but no ansible-core.
# The lab apt mirror (apt.cttb) carries ansible in noble universe.
log "stage 1/5: apt-install bootstrap toolbelt"
export DEBIAN_FRONTEND=noninteractive
apt-get update -o Acquire::Retries=3 -qq
apt-get install -y --no-install-recommends \
    ansible-core ca-certificates curl rsync git \
    || die "apt-install of bootstrap toolbelt failed"

# ── 2. fetch tarball + verify sha256 ───────────────────────────────────────
log "stage 2/5: fetch ${TARBALL_URL}"
mkdir -p "${WORK_DIR}"
TMP_TAR="$(mktemp --suffix=.tar.gz)"
TMP_SHA="$(mktemp --suffix=.sha256)"
trap 'rm -f "${TMP_TAR}" "${TMP_SHA}"' EXIT

curl --retry 3 --retry-delay 5 --connect-timeout 10 --max-time 600 \
     --fail --location --silent --show-error \
     --output "${TMP_TAR}" \
     "${TARBALL_URL}" \
    || die "tarball fetch failed (storehouse unreachable or 404)"

curl --retry 3 --retry-delay 5 --connect-timeout 10 --max-time 30 \
     --fail --location --silent --show-error \
     --output "${TMP_SHA}" \
     "${SHA256_URL}" \
    || die "sha256 sidecar fetch failed"

# Sanity-check tarball size — a sub-100 KiB result is almost certainly an
# h5ai HTML index page that managed to 200, not the actual tarball.
TAR_SIZE="$(stat -c%s "${TMP_TAR}")"
[[ "${TAR_SIZE}" -gt 102400 ]] || die "tarball implausibly small (${TAR_SIZE} bytes) — wrong URL?"

# Verify integrity. Expected sha256 sidecar shape: "<hex>  <filename>\n".
EXPECTED_SHA="$(awk '{print $1}' "${TMP_SHA}")"
ACTUAL_SHA="$(sha256sum "${TMP_TAR}" | awk '{print $1}')"
[[ "${EXPECTED_SHA}" == "${ACTUAL_SHA}" ]] \
    || die "sha256 mismatch — expected ${EXPECTED_SHA}, got ${ACTUAL_SHA}"
log "sha256 verified: ${ACTUAL_SHA}"

# ── 3. extract over WORK_DIR ───────────────────────────────────────────────
log "stage 3/5: extract tarball into ${REPO_DIR}"
rm -rf "${REPO_DIR}"
mkdir -p "${REPO_DIR}"
tar -xzf "${TMP_TAR}" -C "${REPO_DIR}" --strip-components=1 \
    || die "tarball extraction failed"

# ── 4. bulk apt install + remove ───────────────────────────────────────────
# ONE transaction for every host-agnostic package, then ONE remove. The
# Python extractor that built the lists already dropped templated-var names
# (per-host inventory layers) and resolved install/remove conflicts.
log "stage 4/5: bulk apt install + remove from package lists"
cd "${REPO_DIR}"

install_count="$(read_pkg_list "${PKG_INSTALL_LIST}" | wc -l)"
remove_count="$(read_pkg_list  "${PKG_REMOVE_LIST}"  | wc -l)"
log "package lists: install=${install_count} remove=${remove_count}"

if (( install_count > 0 )); then
    # xargs -r so an empty list is a no-op. Recommends are kept (no
    # --no-install-recommends) so the lab desktop gets a stock-lubuntu
    # end-state: gimp's helper plugins, libreoffice's full font/dictionary
    # set, vlc's codec recommends, etc. The role's per-task installs (which
    # become idempotent no-ops after this) historically used recommends too.
    read_pkg_list "${PKG_INSTALL_LIST}" \
        | xargs -r apt-get install -y \
        || die "bulk apt install failed"
else
    log "install list is empty — skipping apt install"
fi

if (( remove_count > 0 )); then
    read_pkg_list "${PKG_REMOVE_LIST}" \
        | xargs -r apt-get remove -y --purge --auto-remove \
        || die "bulk apt remove failed"
else
    log "remove list is empty — skipping apt remove"
fi

# ── 5. run the play (config-only at this point) ────────────────────────────
log "stage 5/5: ansible-playbook build-sudhanix-autobootstrap.yml"
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
