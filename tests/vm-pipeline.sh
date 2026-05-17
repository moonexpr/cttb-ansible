#!/usr/bin/env bash
# gh-22: local throwaway-VM test pipeline for the Sudhanix Ansible roles.
#
# Boots a clean Ubuntu 24.04 (noble) multipass VM, wires it into
# inventory/vm.ini as a dvgs_cs_lab host, runs the Sudhanix rollout
# play against it, and tears it down — so a role change can be validated
# on the developer laptop before it ever touches dvgs-testmachine.
#
# Why multipass: one-line `multipass launch noble`, fast on macOS/Linux,
# no Vagrantfile/boilerplate, no provider lock-in.
#
# Usage:
#   tests/vm-pipeline.sh up        # launch VM + populate inventory/vm.ini
#   tests/vm-pipeline.sh run       # run the rollout play against the VM
#   tests/vm-pipeline.sh test      # up + run (full cycle, fails non-zero on failed>0)
#   tests/vm-pipeline.sh clean     # delete + purge the VM
#
# Requires: multipass (https://multipass.run), ansible, repo checked out.
set -euo pipefail

VM_NAME="${SUDHANIX_VM_NAME:-sudhanix-vm}"
VM_IMAGE="${SUDHANIX_VM_IMAGE:-noble}"
VM_CPUS="${SUDHANIX_VM_CPUS:-2}"
VM_MEM="${SUDHANIX_VM_MEM:-4G}"
VM_DISK="${SUDHANIX_VM_DISK:-20G}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INV="${REPO_ROOT}/inventory/vm.ini"
PLAY="${REPO_ROOT}/plays/sudhanix26-rollout-stage2.yml"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH" >&2; exit 2; }; }

cmd_up() {
  need multipass
  if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
    echo ">> launching $VM_NAME ($VM_IMAGE, ${VM_CPUS}cpu/${VM_MEM}/${VM_DISK})"
    multipass launch "$VM_IMAGE" --name "$VM_NAME" \
      --cpus "$VM_CPUS" --memory "$VM_MEM" --disk "$VM_DISK"
  fi
  local ip
  ip="$(multipass info "$VM_NAME" --format csv | awk -F, 'NR==2{print $3}')"
  [ -n "$ip" ] || { echo "ERROR: could not read VM IP" >&2; exit 1; }
  # multipass injects the host SSH key for the 'ubuntu' user.
  sed -i.bak "s/^sudhanix-vm .*/sudhanix-vm ansible_host=${ip} ansible_user=ubuntu ansible_python_interpreter=\/usr\/bin\/python3/" "$INV"
  rm -f "${INV}.bak"
  echo ">> $VM_NAME ready at $ip; inventory/vm.ini updated"
}

cmd_run() {
  need ansible-playbook
  grep -q PLACEHOLDER_IP "$INV" && { echo "ERROR: run 'up' first (inventory not populated)" >&2; exit 1; }
  echo ">> applying $PLAY to $VM_NAME"
  ansible-playbook "$PLAY" -i "$INV" -l "$VM_NAME" --diff
}

cmd_clean() {
  need multipass
  multipass delete "$VM_NAME" --purge 2>/dev/null || true
  sed -i.bak "s/^sudhanix-vm .*/sudhanix-vm ansible_host=PLACEHOLDER_IP ansible_user=ubuntu ansible_python_interpreter=\/usr\/bin\/python3/" "$INV"
  rm -f "${INV}.bak"
  echo ">> $VM_NAME purged; inventory/vm.ini reset"
}

case "${1:-}" in
  up)    cmd_up ;;
  run)   cmd_run ;;
  test)  cmd_up; cmd_run ;;
  clean) cmd_clean ;;
  *) echo "usage: $0 {up|run|test|clean}" >&2; exit 64 ;;
esac
