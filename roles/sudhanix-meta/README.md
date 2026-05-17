# sudhanix-meta (gh-77)

Ships the Sudhanix 26 lab-desktop transformation as a Debian
metapackage, replacing the manual `ansible-playbook` step after
PXE-install. Published to `apt.cttb cttb-repos` (same pipeline as
`vajra`).

## Status: Phase 0 (skeleton)

This is **only** the build-pipeline proof. The `.deb` installs a marker
file (`/var/lib/sudhanix-meta/installed`) and nothing else. It exists to
confirm `dpkg-buildpackage → reprepro → apt.cttb` works end to end
before any real config migration.

Phases 1-9 (per the issue) each land as their own PR-sized chunk:
Depends: closure, theme/plymouth data, xfconf XML, greeter conf,
postinst alternatives/MIME, panel/keybinds, autoinstall switch,
`roles/sudhanix-core` deprecation.

## Build (on the buildworker LXC)

```
cttb-ct.sh exec buildworker
git clone moonexpr/cttb-ansible && cd cttb-ansible/roles/sudhanix-meta
make build      # ../sudhanix-meta_26.0.0_all.deb
make publish    # scp + reprepro includedeb noble  (operator-run)
```

## Layout

```
debian/        native (3.0) packaging — control, rules, changelog,
               copyright, source/format, *.install, *.postinst
data/          payload tree (Phase 0: a single README marker)
tasks/main.yml ansible callsite — `apt install sudhanix-meta`, opt-in
               via `sudhanix_meta_install: true` until phases land
Makefile       build / publish / clean
```

Version scheme: aligned to the Sudhanix release (`26.0.0`).
