# Local VM test pipeline (gh-22)

Validate Sudhanix Ansible role changes against a throwaway Ubuntu 24.04
VM on your laptop **before** touching `dvgs-testmachine`.

## Prerequisites

- [multipass](https://multipass.run) (`brew install --cask multipass` on
  macOS; `snap install multipass` on Linux dev boxes — dev laptops only,
  never lab hosts).
- `ansible` (the repo's normal controller toolchain; `source utils/setup-env`).

## Use

```bash
tests/vm-pipeline.sh up      # launch the noble VM, wire inventory/vm.ini
tests/vm-pipeline.sh run     # apply plays/sudhanix26-rollout-stage2.yml to it
tests/vm-pipeline.sh test    # up + run in one shot
tests/vm-pipeline.sh clean   # delete + purge the VM, reset the inventory
```

The VM joins the `dvgs_cs_lab` group in `inventory/vm.ini`, so it
receives the same role set (`sudhanix-core` → `common`,
`sudhanix-vajra-tool`) a real DVGS lab desktop gets. `inventory/vm.ini`
is a standalone stub — it is never merged into
`inventory/sudhanix26_hosts.ini`, so production `hosts: all` plays can
never reach the VM.

A successful `test` ends with a `PLAY RECAP` of `failed=0`. A non-zero
`failed` count fails the script (CI-friendly).

Tunables via env: `SUDHANIX_VM_NAME`, `SUDHANIX_VM_IMAGE`,
`SUDHANIX_VM_CPUS`, `SUDHANIX_VM_MEM`, `SUDHANIX_VM_DISK`.

## Scope / caveats

- The VM has no LDAP/NFS/CUPS campus services, so credential-dependent
  roles (`ldap-client`, `nfs-home`, `cups-client`) are expected to no-op
  or skip — this pipeline validates the **host-agnostic desktop
  transformation**, the same boundary `sudhanix-autostrap`/`sudhanix-meta`
  draw. It is not a substitute for the final `dvgs-testmachine`
  integration test, it is the fast pre-check before it.
