---
name: cttb-pxe-wait
user-invocable: false
description: >
  Wait for a CTTB host to complete a PXE-install cycle: leave the
  network, autoinstall, come back online, accept SSH. Agent-only
  helper extracted from `sudhanix26-rollout.yml`'s stage1 → stage2
  bridge, for cases where a host has already been triggered to
  reboot into PXE and the agent needs to wait before proceeding.
  Refuses to operate without a single named host alias.
---

# cttb-pxe-wait

One job: block until a host that's in the middle of a PXE-install cycle is back up and accepting SSH. Agent-only — the assumption is that the host is already rebooting into PXE; this skill only waits.

## Procedure

Run the resource script:

```
bash .claude/skills/cttb-pxe-wait/scripts/pxe-wait.sh <alias> [--skip-down]
```

The script does three phases, each with a timeout:

1. **Wait for down** — `wait_for: state=stopped port=22 host=<alias>` with a 600s timeout. Skipped when `--skip-down` is passed (use when the agent knows the host is already offline). Confirms the PXE cycle has actually started.
2. **Wait for install** — sleep 120s probe delay (the host is in the autoinstaller; probing too early returns nothing useful), then `wait_for: state=started port=22 host=<alias>` with a 3600s timeout. Allows up to one hour for the autoinstall to complete.
3. **Verify SSH** — one round-trip `ssh <alias> hostname` to confirm the new system answers ssh, not just port 22.

Tunables via env vars: `PXE_DOWN_TIMEOUT` (default 600), `PXE_INSTALL_TIMEOUT` (default 3600), `PXE_PROBE_DELAY` (default 120).

Success prints `[cttb-pxe-wait] <alias> back up: <hostname>` to stderr and exits 0. On timeout, exits non-zero with the phase that timed out in the message.

## When this skill is the right tool

- Another skill or routine just triggered a PXE reboot (efibootmgr nextboot, or a remote reboot into PXE) and needs to chain follow-up work on the post-install image.
- The agent is doing a destructive reimage and needs the wait phase isolated from the trigger and the configure phases.

## When this skill is NOT the right tool

- Routine reboot (no PXE involved) — the host is back in seconds; just `ssh <alias> hostname` directly.
- End-to-end reimage (trigger + wait + configure) — use `plays/sudhanix26-rollout.yml` which already chains all three.
- Host has never been provisioned — this skill assumes a known SSH alias resolves; first-touch PXE is a different flow.

## Prerequisites

- The host alias resolves via inventory or `~/.ssh/config`.
- Operator on campus network (the wait depends on continuous reachability).

## Resources

| File | Loaded / run when |
|---|---|
| `scripts/pxe-wait.sh` | Run on every cttb-pxe-wait invocation. The actual wait pipeline. |
