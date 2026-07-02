#!/usr/bin/env bash
# vajra-build / scripts/publish.sh
#
# End-to-end vajra .deb publish pipeline. Run by /vajra-build (SKILL.md).
# Stages source, builds on buildworker LXC, ships via reprepro to
# apt.cttb's noble/main/amd64 pool, cleans up, stops the container.

set -euo pipefail

VAJRA_SRC="${VAJRA_SRC:?set VAJRA_SRC to your local vajra source checkout (see .claude/.env.example)}"
STAGE_DIR="${STAGE_DIR:-/tmp/vajra-stage}"
WORK_DIR=/root/vajra-build
REPO_BASE=/srv/cttb-repos/apt/ubuntu
DIST=noble

step() { echo "=== [$1] $2" >&2; }
fail() { echo "[vajra-build] ERROR at step $1: $2" >&2; exit 1; }

# Read exact .deb filename from Cargo.toml so the pipeline doesn't rely on globs.
VERSION=$(awk -F\" '/^version =/ {print $2; exit}' "$VAJRA_SRC/vajra-gtk/Cargo.toml" 2>/dev/null || true)
REVISION=$(awk -F\" '/^revision =/ {print $2; exit}' "$VAJRA_SRC/vajra-gtk/Cargo.toml" 2>/dev/null || true)
[ -n "$VERSION" ]  || fail 0 "could not read [package].version from $VAJRA_SRC/vajra-gtk/Cargo.toml"
[ -n "$REVISION" ] || REVISION=1
DEB_NAME="vajra_${VERSION}-${REVISION}_amd64.deb"
echo "[vajra-build] target deb: $DEB_NAME" >&2

# Track success so the EXIT trap knows whether to delete the work dir.
SUCCESS=0
cleanup() {
  step exit "cleanup + stop buildworker"
  if [ "$SUCCESS" = "1" ]; then
    ssh srv-vm "lxc exec buildworker -- rm -rf $WORK_DIR && rm -f /tmp/$DEB_NAME" 2>/dev/null || true
    ssh srv-nas "rm -f /tmp/$DEB_NAME && sudo lxc exec debmirror -- rm -f /tmp/$DEB_NAME" 2>/dev/null || true
    rm -rf "$STAGE_DIR" "/tmp/$DEB_NAME" 2>/dev/null || true
  else
    echo "[vajra-build] partial-failure: leaving $WORK_DIR on buildworker for debugging" >&2
  fi
  ssh srv-vm "lxc stop buildworker" 2>/dev/null || true
}
trap cleanup EXIT

# 1. Stage source.
step 1 "rsync source -> $STAGE_DIR (anchored excludes)"
rm -rf "$STAGE_DIR"
rsync -a \
  --exclude='/target/' \
  --exclude='/.git/' \
  --exclude='/legacy/' \
  --exclude='.DS_Store' \
  --exclude='._*' \
  "$VAJRA_SRC/" "$STAGE_DIR/" || fail 1 "rsync failed"

# 2. Bring buildworker up.
step 2 "lxc start buildworker"
ssh srv-vm "lxc start buildworker 2>/dev/null || true" || fail 2 "lxc start failed"

# 3. Push source into the container.
step 3 "tar pipe source -> buildworker:$WORK_DIR"
tar c -C "$STAGE_DIR" . 2>/dev/null \
  | ssh srv-vm "lxc exec buildworker -- bash -c 'rm -rf $WORK_DIR && mkdir -p $WORK_DIR && tar x -C $WORK_DIR 2>/dev/null'" \
  || fail 3 "tar/lxc exec push failed"

# 4. Build.
step 4 "cargo build --release --workspace && cargo deb --no-build -p vajra-gtk"
ssh srv-vm "lxc exec buildworker -- bash -c 'source /root/.cargo/env && cd $WORK_DIR && cargo build --release --workspace && cargo deb --no-build -p vajra-gtk'" \
  || fail 4 "cargo build/deb failed (check buildworker output)"

# 5. Pull .deb out of the container.
step 5 "lxc file pull $DEB_NAME -> srv-vm:/tmp/"
ssh srv-vm "lxc file pull buildworker$WORK_DIR/target/debian/$DEB_NAME /tmp/$DEB_NAME" \
  || fail 5 "lxc file pull failed"

# 6. Bridge via mac to srv-nas (direct srv-vm -> srv-nas scp has been flaky).
step 6 "bridge $DEB_NAME via mac to srv-nas"
scp -q "srv-vm:/tmp/$DEB_NAME" "/tmp/$DEB_NAME"  || fail 6 "scp srv-vm -> mac failed"
scp -q "/tmp/$DEB_NAME" "srv-nas:/tmp/$DEB_NAME" || fail 6 "scp mac -> srv-nas failed"

# 7. Reprepro publish + verify.
step 7 "reprepro includedeb $DIST + verify"
PUBLISH_OUT=$(ssh srv-nas "sudo lxc file push /tmp/$DEB_NAME debmirror/tmp/$DEB_NAME && sudo lxc exec debmirror -- bash -lc '
  set -e
  reprepro -b $REPO_BASE remove $DIST vajra 2>/dev/null || true
  reprepro -b $REPO_BASE includedeb $DIST /tmp/$DEB_NAME >/dev/null
  reprepro -b $REPO_BASE export $DIST >/dev/null
  reprepro -b $REPO_BASE list $DIST vajra
'") || fail 7 "reprepro publish failed"

VERIFY_LINE=$(echo "$PUBLISH_OUT" | grep "^$DIST|" || true)
[ -n "$VERIFY_LINE" ] || fail 7 "reprepro published but list did not return a $DIST line"

SUCCESS=1
echo "" >&2
echo "[vajra-build] published: $VERIFY_LINE" >&2
