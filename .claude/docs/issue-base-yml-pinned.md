`plays/base.yml` is the only play that carries the `common` role, and it is pinned to a single hardcoded host:

```yaml
- hosts: drbu-cs-lab-pc1
  roles:
    - common
```

`--limit` can only narrow a play's host pattern, never widen it. So the `common` role — baseline packages, SSH key distribution, logging, wake-on-LAN — cannot be applied to any other host through a play. Every other use has to be an ad-hoc `ansible -m copy` that reproduces the role's tasks by hand, which defeats the point of having the role and silently drifts from it.

## Repro

```bash
utils/pb base --limit drbu-sw-cslab-w-pc2.cttb --tags wake_on_lan --diff
```

## Expected

The `common` role's `wake_on_lan` tasks run against `drbu-sw-cslab-w-pc2.cttb`.

## Actual

```
[WARNING]: Could not match supplied host pattern, ignoring: drbu-cs-lab-pc1

PLAY [drbu-cs-lab-pc1] *********************************************************
skipping: no hosts matched

PLAY RECAP *********************************************************************
```

Nothing runs, and the recap is empty rather than an error — it reads like a successful no-op.

Note the pinned name `drbu-cs-lab-pc1` does not even exist in `inventory/sudhanix26_hosts.ini` (the CS lab hosts are `drbu-sw-cslab-w-pc1` … `drbu-sw-cslab-m-pc3`), so the play matches nothing at all against the default inventory.

## Repo locations

- `plays/base.yml:3` — the pinned host pattern
- `plays/sudhanix26-rollout-stage2.yml` — the play that already does this correctly (`hosts: all`, documented as "-l is what scopes a run", with an explicit warning that there is no safe bare invocation)

## Acceptance criteria

- [ ] `utils/pb base -l <host-or-group>` applies the `common` role to that host or group
- [ ] The play documents that there is no safe bare invocation, matching the stage-2 convention
- [ ] Applying `--tags wake_on_lan` to a single lab desktop works end to end

## Where to look first

Change `hosts:` to `all` and carry over the header comment from `sudhanix26-rollout-stage2.yml`. The risk being guarded against is a bare `utils/pb base` hitting every host in the inventory including servers and the `pxe` entry, which that convention already handles by documenting it rather than by pinning.

## Context

Hit 2026-08-06 while rolling out the wake-on-LAN arming fix (#118) to lab desktops. The fix lives in the `common` role under the existing `wake_on_lan` tag, and there was no way to deploy it through a play — it had to go out as an ad-hoc `ansible -m copy` of each file the role manages.
