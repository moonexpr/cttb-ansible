## Repro

```bash
# On rui-desktop2, any sysadmin copy of the fleet key:
ssh-keygen -y -f ~/.ssh/cttb-os     # prompts for a passphrase nobody can supply
# Operator confirmation, 2026-07-29: "cttb-os passphrase is unknown"
```

## Expected

The fleet automation identity (`ansible@cttb.us`, RSA 4096,
`SHA256:W0khOQ0eKyaGYVjXKyIhrPGVl1WjDrTPpcTlWv8WKOg`, enrolled as
`roles/common/files/ssh_keys/ansible.pub`) is usable by any authorized
sysadmin from a cold start: its passphrase is known, escrowed in a
credential store, or the key is rotated to one that is.

## Actual

Every known private copy (`~/.ssh/cttb-os` for kit.chong, frankliu,
jerryhsu, ruiliu on rui-desktop2; jc on WORKSTATION) is locked with a
passphrase no one can produce. The key is usable **only** through
long-lived `ssh-agent` processes on rui-desktop2 (e.g. kit.chong's,
env stashed in `~kit.chong/tt` per `~/.ssh/load-cttb-key.txt`). A single
reboot of rui-desktop2 kills those agents and with them all
administrator@ fleet access via this key — the trust anchor
`docs/sysadmin-onboarding.md` §8 depends on ("their already-trusted key
authorizes the SSH connection that installs yours").

Tested and ruled out as the passphrase: `CTTB_VAULT_PASS`, the legacy
kit.chong sudo password from the old skill docs.

## Repo locations

- `/roles/common/files/ssh_keys/ansible.pub` (the public half)
- `/docs/sysadmin-onboarding.md` §8 (trust-chain doc)
- `/plays/distribute-ssh-keys.yml`, `/plays/distribute-ssh-keys-infra.yml`

## Acceptance criteria

- [ ] A fleet automation key exists whose passphrase is known and stored
      in the platform credential store (per CLAUDE.md Credentials) or
      formally escrowed.
- [ ] It is enrolled in `roles/common/files/ssh_keys/` and distributed
      (both plays), so cold-start fleet access does not depend on any
      surviving agent process.
- [ ] The old `ansible@cttb.us` key's retirement is decided and recorded
      (full removal is gated on the missing revocation path, #96).
- [ ] `docs/sysadmin-onboarding.md` documents how a sysadmin loads the
      new key without folklore files like `load-cttb-key.txt`.

## Workaround

While kit.chong's agent survives on rui-desktop2:

```bash
sudo -u kit.chong bash -c 'source ~/tt; ssh administrator@<host> ...'
```

Also mitigating: jc's personal key was distributed fleet-wide on
2026-07-29 (reachable hosts), providing a second, passphrase-independent
administrator path from WORKSTATION.

## Where to look first

Whether the passphrase can be recovered from any sysadmin's memory or
password manager before deciding to rotate. If not: rotation =
new keypair → enroll in `ssh_keys/` → run both distribute plays from a
host with working access.

## Context

Surfaced 2026-07-29 while distributing jc's key: every non-interactive
auth attempt with cttb-os failed until kit.chong's running agent was
found. Related: #96 (no revocation path), #97 (PXE-imaged hosts miss
canonical keys — a rotated key would not reach freshly imaged hosts
either).
