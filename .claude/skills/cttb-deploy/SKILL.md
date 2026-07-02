---
name: cttb-deploy
user-invocable: false
description: >
  Run a tag-scoped Ansible deploy against a single CTTB host via
  `sudhanix26-rollout-stage2.yml`, with all paranoid flags pre-set
  (vault password, become-pass, --skip-tags zoom, --diff). Agent-only
  helper. Triggers when another skill or routine needs to deploy a
  subset of role tasks to one named host — e.g., post-build vajra
  install, theme drop, single-role iteration. Refuses to run without
  --limit; never fleet-wide.
---

# cttb-deploy

Single-host, tag-scoped Ansible deploy. One job: invoke `plays/sudhanix26-rollout-stage2.yml` against one host with the right tags and the right secrets, surface the recap, exit with the playbook's exit code.

This skill is agent-only because the invocation is the kind of thing humans should think about (which tags, against which host) before running. Agents that already know both should call it. Humans should drive deploys via a direct `ansible-playbook` line, with the cargo-cult-prone flags visible.

## Procedure

Run the resource script:

```
bash .claude/skills/cttb-deploy/scripts/deploy.sh <alias> <tags> [--check]
```

The script:

1. Validates that `<alias>` is a non-empty host name and `<tags>` is non-empty. Refuses fleet-wide deploys (no `--limit all`, no `--limit @group`).
2. Verifies `CTTB_VAULT_PASS` is reachable via the macOS Keychain through `.claude/sysadmin/vault-pass.sh`.
3. Invokes `ansible-playbook -i inventory/hosts plays/sudhanix26-rollout-stage2.yml --limit <alias> --tags <tags> --skip-tags zoom --diff --vault-password-file .claude/sysadmin/vault-pass.sh -e ansible_become_pass=$(.claude/sysadmin/vault-pass.sh)`. Adds `--check` when the third arg is present.
4. Exits with the playbook's exit code.

The Ansible recap is the success signal: `ok=N changed=M unreachable=0 failed=0`.

## Why the paranoid flags

- **`--limit <alias>`** — never fleet-wide. The script refuses to run without a single named host. Lab fleet rollout is operator-gated and goes through `sudhanix26-rollout.yml`, not this skill.
- **`--vault-password-file .claude/sysadmin/vault-pass.sh`** — reads `CTTB_VAULT_PASS` from macOS Keychain on every invocation. No password on disk, no shell history exposure.
- **`-e ansible_become_pass="$(...)"`** — the PXE-installed `administrator` cloud-init identity is an ordinary sudoer; privileged tasks need become-pass. Vault password doubles as sudo for the testmachine slot per project memory.
- **`--skip-tags zoom`** — broken Zoom .deb archive signature. Omitting the skip fails the run.
- **`--diff`** — review-friendly output. Always on; the cost is negligible.

## Prerequisites

- Operator on campus network (Ansible hangs on a dropped SSH session — see project memory `feedback_deploy_roaming_network`).
- `CTTB_VAULT_PASS` populated in macOS Keychain.
- The target host reachable via the inventory's ssh chain.

If any precondition fails, the underlying ansible-playbook surfaces the error — the script does not try to be smarter than ansible.

## Resources

| File | Loaded / run when |
|---|---|
| `scripts/deploy.sh` | Run on every cttb-deploy invocation. The actual wrapper. |
