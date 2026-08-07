## Repro

On any Sudhanix 26 host after vajra branding has applied (e.g. a freshly
stage2-completed DRBU cslab machine):

```bash
grep CODENAME /etc/os-release
# VERSION_CODENAME=storehouse
# UBUNTU_CODENAME=storehouse        <-- defect

# any codename-deriving apt tooling then fails, e.g.:
ansible <host> -b -m apt_repository -a "repo=ppa:stellarium/stellarium-releases"
# E: The repository 'https://ppa.launchpadcontent.net/stellarium/stellarium-releases/ubuntu storehouse Release' does not have a Release file.
```

## Expected

Branding may set `NAME`, `VERSION`, `ID`, `VERSION_CODENAME` etc. to
Sudhanix values, but `UBUNTU_CODENAME` must stay `noble` — that field
exists precisely to name the upstream base for tools that need it
(PPA suite resolution, third-party installers, `add-apt-repository`).

## Actual

`UBUNTU_CODENAME=storehouse` in `/etc/os-release`. The `/etc/os-release`
symlink is replaced by a regular file; pristine values survive only in
`/usr/lib/os-release`. Failure signature during the DRBU cslab rollout
(stage2 rerun, `common : add additional apt repo`):

```
E:The repository 'https://ppa.launchpadcontent.net/stellarium/stellarium-releases/ubuntu storehouse Release' does not have a Release file.
```

First runs pass because the repo task precedes branding; every rerun on a
branded host failed until the ansible-side workaround landed.

## Repo locations

- Branding source: vajra codebase (`$VAJRA_SRC`), os-release rewrite path — not in cttb-ansible.
- Ansible workaround: /Users/jc/GitRepos/cttb-ansible/roles/common/tasks/setup/default.yml ("resolve the underlying Ubuntu codename")

## Acceptance criteria

- [ ] vajra branding leaves `UBUNTU_CODENAME=noble` in `/etc/os-release`
- [ ] rebranding an already-branded host is idempotent (no second-pass drift; observed: UBUNTU_CODENAME was still `noble` after run 1 and became `storehouse` only after a rerun)
- [ ] `apt_repository` with a `ppa:` spec works on a branded host without the roles/common codename override
- [ ] new vajra .deb published to apt.cttb extras (noble)

## Workaround

Committed in roles/common (resolve codename from `/usr/lib/os-release`,
pass `codename:` to `apt_repository`):

```yaml
- name: resolve the underlying Ubuntu codename
  command: sh -c '{ . /usr/lib/os-release 2>/dev/null || . /etc/os-release; } && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"'
```

## Where to look first

vajra's branding/os-release writer — whatever templates or sed-rewrites
`/etc/os-release` (the second-pass `UBUNTU_CODENAME` clobber suggests a
global `noble -> storehouse` substitution rather than field-scoped edits).
Related history: #14 (branding sweep: remove residual Ubuntu strings) —
this looks like that sweep overshooting into the one field that must keep
the Ubuntu name.

## Context

Discovered 2026-07-31 during the DRBU cslab sudhanix26 rollout while
re-running stage2 (reruns became routine due to unrelated failures).
Mattered because it made stage2 non-rerunnable on any branded host —
worked around in cttb-ansible, but the underlying field is wrong on every
deployed Sudhanix 26 desktop.
