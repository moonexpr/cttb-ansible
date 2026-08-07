## Repro

```bash
cd ~/cttb-ansible
grep -rn 'dvgs-testmachine\|10\.11\.30\.60' --include='*.md' --include='*.yml' . | grep -v '^./logs/'
```

Returns ~19 hits. The functional one:

```bash
utils/pb test-vajra-pr -l dvgs-testmachine
```

## Expected

Docs and plays reference the host that actually exists. `plays/test-vajra-pr.yml`
targets a real host and runs its tasks.

## Actual

`dvgs-testmachine` was retired on 2026-05-20 — `inventory/sudhanix26_hosts.ini:293-294`
carries the tombstone comment `# (slot vacated 2026-05-20 — dvgs-testmachine reverted
to dvgs-lab3)`. The real host is `dvgs-lab3.cttb` at 10.11.9.23
(`inventory/sudhanix26_hosts.ini:72`).

`plays/test-vajra-pr.yml:13` still declares `hosts: dvgs-testmachine`, which now matches
zero inventory hosts. Ansible reports `skipping: no hosts matched` and exits 0 — a
**silent no-op**, not an error, so a vajra PR can appear to have been tested when nothing
ran. This is the part that is a defect rather than drift.

The remainder is documentation drift that sends a sysadmin at a host that is not there,
including the stale address 10.11.30.60.

## Repo locations

Functional:
- `/Users/jc/GitRepos/cttb-ansible/plays/test-vajra-pr.yml:13` — `hosts: dvgs-testmachine`

Comments and docs:
- `/Users/jc/GitRepos/cttb-ansible/plays/sudhanix-distributed.yml:17` — usage comment
- `/Users/jc/GitRepos/cttb-ansible/PROJECT.md` — lines 41, 42, 45, 48, 51, 79, 82, 89, 90, 105, 114, 157, 251
- `/Users/jc/GitRepos/cttb-ansible/README.md:279` — "`dvgs-testmachine` is the validation host"
- `/Users/jc/GitRepos/cttb-ansible/docs/sysadmin-onboarding.md:227` — `ssh-copy-id administrator@10.11.30.60`

Already corrected (out of scope here, listed so the sweep does not redo them):
- `PROJECT.md:31` and `PROJECT.md:231` — the two `util-screenshot` invocations, fixed
  alongside the `plays/util-screenshot.yml` repair.

## Acceptance criteria

- [ ] `plays/test-vajra-pr.yml` targets a host that exists in inventory, or is deleted if
      the workflow it supported is gone.
- [ ] A run against a nonexistent host limit fails loudly rather than exiting 0 — decide
      whether to add `any_errors_fatal` / an explicit host-count assertion to the
      dev-test plays, so "no hosts matched" cannot read as success.
- [ ] `grep -rn 'dvgs-testmachine\|10\.11\.30\.60' --include='*.md' --include='*.yml' .`
      (excluding `logs/`) returns no hits outside the inventory tombstone comment.
- [ ] `README.md:279` names the current validation host.

## Workaround

Substitute the real host at the command line:

```bash
utils/pb test-vajra-pr -l dvgs-lab3
ssh administrator@dvgs-lab3.cttb    # not 10.11.30.60
```

## Where to look first

`inventory/sudhanix26_hosts.ini:293-294` is the tombstone that explains the rename and is
the anchor for the sweep. `plays/test-vajra-pr.yml:13` is the only hit where the staleness
changes behavior rather than just misleading a reader — start there, then the docs sweep is
mechanical.

Worth deciding as part of this: whether dev-test plays should hard-fail on an empty host
match. Ansible's default (exit 0 on "no hosts matched") is what turns a renamed host into a
test that silently stops running.

## Context

Found on 2026-06-11 while repairing `plays/util-screenshot.yml`, which had never worked
(it set `DISPLAY=:0` with no `XAUTHORITY` and no `become`; failure recorded at
`logs/runtime.log:28602`). Fixing that play meant correcting the two `PROJECT.md` lines
prescribing it, and a sweep for other references to the same retired host turned up the
rest. The `util-screenshot` work is complete; this issue is the deliberately-deferred
remainder, filed rather than absorbed so the screenshot fix stayed reviewable.
