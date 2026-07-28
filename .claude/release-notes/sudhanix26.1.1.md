# Sudhanix 26.1.1 — Accessible Credential Handling

Released 2026-07-28. Previous release: [`sudhanix26.1.0`](https://github.com/moonexpr/cttb-ansible/releases/tag/sudhanix26.1.0) (2026-05-20).

A maintenance release, named for the question it turned out to be about: can a sysadmin who is not on a Mac actually use this repository? Until this release the honest answer was no.

No change to the deployed desktop image. `sudhanix_release` remains `26` on the Ubuntu 24.04 (noble) base, so a host built from 26.1.0 and one built from 26.1.1 are the same machine, and **no fleet run is required**.

---

## Highlights

- **One credential path, four backends** — macOS Keychain, Windows Credential Manager, Linux Secret Service, and a mode-0600 file store for headless hosts and bare WSL shells.
- **`--vault-password-file` removed from every command line**, because `ansible.cfg` now carries `vault_password_file`.
- **SSH key enrollment is a one-file pull request** — drop a `.pub` into `roles/common/files/ssh_keys/`.
- **A workstation onboarding guide** covering macOS, Windows/WSL, and Debian, at `docs/sysadmin-onboarding.md`.
- **`requirements.yml`**, declaring the three collections the roles have always used but never named.
- **The CityLights skin** replaces the `cttb-dark.css` overlay on `wiki.cttb`.

> **Action required:** every sysadmin must store `CTTB_VAULT_PASS` in their platform credential store. The old `$CTTB_VAULT_PASS` environment-variable path no longer works. See [What this asks of you](#what-this-asks-of-you).

---

## Changelog

- Retired the bash `CTTB_VAULT_PASS` resolver in favour of the shared Python credential layer, adding the Linux (`secret-tool`) and 0600-file backends it lacked. `ChainedStore` tries each in order; a world-readable secret file raises rather than being masked.
- Set `vault_password_file` in `ansible.cfg`. Deleted `cttb-vault.sh`, whose only job was injecting that flag, and removed the flag from README, DEPLOYMENT, the deploy skill, and every play comment.
- `vault-pass` now exits 2 rather than returning an empty password.
- `roles/common` installs every `*.pub` in `roles/common/files/ssh_keys/` via `with_fileglob`. `roles/storehouse` reads that same directory through `role_path`; its duplicate copy is deleted.
- Added `requirements.yml` — `ansible.posix`, `community.general`, `community.mysql`.
- Added `docs/sysadmin-onboarding.md` and `docs/ssh_config.example`.
- Replaced `cttb-dark.css` (~470 lines of Vector patches) with the CityLights skin (~1,600 lines, plus hooks, i18n, and light/dark `p31m` assets). Updated `LocalSettings.php.j2` and the `mediawiki` role.
- Shipped the `.claude/` sysadmin toolkit with the repository; added `SECURITY.md`.
- Added the `/release-notes` skill and `.claude/release-notes/` as the source of truth for releases.

---

## Rationale

### Onboarding a new sysadmin now has a documented path

This release exists mainly because two new sysadmins could not get their workstations to a working state, and the repository offered them almost no help. Several gaps compounded, each hiding the next.

Nothing in the repo said how to install Ansible — `README.md` simply asserted it as a precondition. Worse, a *correctly* installed workstation was still broken: the roles call `ansible.posix`, `community.general`, and `community.mysql` by bare module name, but no `requirements.yml` declared them. A modern `ansible-core` install ships no collections at all, and the resulting error names the failing *task*, never the missing collection — so the failure gives no hint of its own cause.

**`docs/sysadmin-onboarding.md`** is the new front door: install steps for macOS, Windows/WSL, and Debian; collection setup; credential storage per platform; SSH config; key enrollment; jump-host mechanics; and a layered verification checklist where each step depends only on the ones above it, so the first failure tells you where to look. **`requirements.yml`** declares the three collections, derived from an actual census of module usage rather than guesswork.

The guide documents four WSL-specific traps that reliably cost people an afternoon: keys stored under `/mnt/c` inherit `0777` from DrvFs and `ssh` refuses them; `ssh-agent` does not persist across WSL shells; a repo cloned with Windows git carries CRLF endings that break `source utils/setup-env`; and WSL's clock drifts after the host sleeps, surfacing as confusing TLS errors.

### SSH host aliases are no longer invisible

Every `cttb-ct.sh` operation depended on host aliases — `srv-vm`, `srv-nas`, `wiki` — that resolved out of an uncommitted, undocumented `~/.ssh/config`. A new sysadmin had no way to discover them.

**`docs/ssh_config.example`** now carries them, installed by `Include` so later updates arrive with a `git pull` rather than a copy-paste. It documents the asymmetry that costs the most time in practice: containers on `srv-vm` are reached with `lxc exec`, but containers on `srv-nas` need `sudo lxc exec`, because the login user there cannot read `/etc/lxc`.

### Enrolling an SSH key is now a one-file pull request

Key enrollment previously meant editing two hardcoded `authorized_key` tasks, duplicated byte-for-byte across `roles/common` and `roles/storehouse`. Adding a person meant touching both.

`roles/common` now installs every `*.pub` in `roles/common/files/ssh_keys/`, so enrolling a sysadmin means dropping one file and opening a PR. `roles/storehouse` reads that same canonical directory instead of keeping its own copy, which is deleted.

Two limits are worth knowing rather than discovering later. The task is `state: present`, so **removing a `.pub` revokes nothing** — deleting a key from the directory leaves it installed on every host ([#96](https://github.com/moonexpr/cttb-ansible/issues/96)). And the `netinstall-2404` and `netinstall` roles still carry their own inlined copies of the older keys, so **a key added today does not reach a host PXE-imaged tomorrow** ([#97](https://github.com/moonexpr/cttb-ansible/issues/97)). Both are tracked; neither is fixed here.

### The vault password works off macOS

The Ansible vault password had its own bash resolver with a private Keychain call and an environment-variable fallback, running parallel to — and inconsistent with — the Python credential layer the `wiki` and `ldap` tools already used. That Python layer supported macOS and Windows and raised an error on everything else. Since WSL reports itself as Linux, **the Python toolkit had never worked there at all**; only the environment-variable fallback kept Linux alive.

The bash machinery is retired. One credential path now serves every platform: macOS Keychain, Windows Credential Manager, Linux Secret Service via `secret-tool`, and a `0600` file store at `~/.config/cttb/secrets/` chained last everywhere, so headless servers, cron jobs, and bare WSL shells resolve credentials too. The file store also replaces the environment variable with something meaningfully safer — an environment variable leaks through `ps`, `/proc/<pid>/environ`, and every child process; a `0600` file does not.

The visible consequence is a simplification: `ansible.cfg` now sets `vault_password_file`, so **`--vault-password-file` disappears from every command line and every document**. `ansible-vault edit <file>` just works. The wrapper script that existed only to inject that flag is deleted rather than rewritten. The helper also fails closed — it exits non-zero rather than handing `ansible-vault` an empty password, which used to surface as a misleading "decryption failed" instead of "your credential is missing."

> **Action required:** every sysadmin must store `CTTB_VAULT_PASS` in their platform credential store. §5 of the onboarding guide gives the exact command per platform. The old `$CTTB_VAULT_PASS` environment-variable path no longer works.

### Wiki: the CityLights skin

`wiki.cttb` moves from the `cttb-dark.css` overlay onto **CityLights**, a proper MediaWiki skin — `skin.json`, PHP hooks, i18n, and about 1,600 lines of stylesheet, replacing roughly 470 lines of patch-on-Vector CSS. Codex theming, sidebar cards, and 32px chrome come with it, along with light and dark `p31m` pattern assets. `LocalSettings.php.j2` and the `mediawiki` role were updated to install and select it.

This supersedes the corpus-sweep audit that had been closing hardcoded-color holes in Vector one at a time.

### Repository and tooling

The `.claude/` sysadmin toolkit now ships with the repository rather than being gitignored, so the skill catalog (`/sysadmin`, `/ldap`, `/wiki-author`, `/cttb-host`, `/cttb-vault`, and the rest) is available on any clone. `SECURITY.md` was added. `CLAUDE.md`, `PROJECT.md`, `README.md`, and `DEPLOYMENT.md` were updated to match the credential and onboarding changes.

A new **`/release-notes`** skill captures the procedure that produced this file, so the next release is a repeat rather than a rediscovery. It carries `release-scope.sh`, which groups the diff since the previous tag by area — the scope above was computed with it rather than recalled from the commit log. This directory, `.claude/release-notes/`, is now the source of truth from which both the tag annotation and the GitHub Release are derived; the `sudhanix26.1.0` tag already pointed here, but the file was never committed because `.claude/` was gitignored at the time.

---

---

## What this asks of you

Nothing to deploy. This release changes the control machine and the wiki, not the fleet:

1. `git pull && git checkout sudhanix26.1.1`
2. `ansible-galaxy collection install -r requirements.yml`
3. Store `CTTB_VAULT_PASS` in your credential store — see `docs/sysadmin-onboarding.md` §5
4. Confirm with `.claude/sysadmin/vault-pass` and `ansible-vault view host_vars/wiki-2404/wiki_vault.yml`

The CityLights skin reaches `wiki.cttb` on the next `mediawiki` role run.

## Known issues

- `vars/jc_passwds.enc.yml` cannot be decrypted with the current credential — it was encrypted with an older, now-unknown password. Pre-existing, not introduced here; only `plays/util-hardware-survey-dbg.yml` loads it ([#95](https://github.com/moonexpr/cttb-ansible/issues/95)).
- Three inventory paths disagree across `ansible.cfg`, `utils/setup-env`, and the deploy skill, so which fleet you see depends on how you invoked Ansible ([#98](https://github.com/moonexpr/cttb-ansible/issues/98)).
- `plays/util-ssh-copy-id.yml` hardcodes a path that exists on no current machine and cannot run ([#99](https://github.com/moonexpr/cttb-ansible/issues/99)).
- SSH ProxyJump over Tailscale remains intermittent; on-campus paths are unaffected.

## Merged

- [#92](https://github.com/moonexpr/cttb-ansible/pull/92) — Ship `.claude/` sysadmin toolkit for team use
- [#93](https://github.com/moonexpr/cttb-ansible/pull/93) — Retire the bash `CTTB_VAULT_PASS` machinery for the Python credential layer
- [#100](https://github.com/moonexpr/cttb-ansible/pull/100) — Sysadmin onboarding runbook, `requirements.yml`, keys-directory enrollment
