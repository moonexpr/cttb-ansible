# PROJECT.md

Project conventions and architecture reference for cttb-ansible.

---

## Stack

- **Language**: Ansible (YAML), Jinja2 templates, Bash
- **Framework**: Ansible 2.x with custom roles
- **Target OS**: Ubuntu 24.04 LTS (migrating from 20.04)
- **Desktop**: XFCE4 (xfwm4, xfce4-panel, Thunar, xfce4-terminal, Plank dock)
- **Theme**: WhiteSur-Dark GTK + WhiteSur-dark icons + WhiteSur-cursors

---

## Git & PRs

- **Commit convention**: Free-form, descriptive
- **Branch strategy**: `feature/ubuntu22-upgrade` is the active development branch. Push directly, no PRs.
- **No co-author lines** in commits
- **Ships with the repo**: `.claude/` (sysadmin toolkit + skills + shared `settings.json`), `CLAUDE.md`, `PROJECT.md` — all secrets redacted.
- **Never commit** personal/runtime state: `.claude/.env`, `.claude/settings.local.json`, `.claude/wiki-pages/`, `.claude/worktrees/`, `.claude/baselines/`, `.claude.bak/`, or sprint/plan/workplan files (`WORKPLAN.md`, `NOTE.md`, `SPRINT_PLAN.md`) to git.

---

## Testing

- **Philosophy**: Deploy to test machine, verify via SSH + remote screenshot
- **Test machine**: `dvgs-lab3.cttb` (10.11.9.23) — the `dvgs-testmachine` slot was vacated 2026-05-20
- **Remote screenshot**: `utils/pb util-screenshot --limit dvgs-lab3.cttb --ask-become-pass`
- **Ansible check mode**: `ansible-playbook plays/desktop.yml --check --diff --limit dvgs-lab3.cttb`

### Incremental Testing

**Always test individual tasks/tags during development** instead of running the full playbook. The full playbook runs 130+ tasks and takes 10+ minutes. Use targeted runs:

```bash
# Run only tasks with a specific tag
source utils/setup-env
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-testmachine --tags browser --diff
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-testmachine --tags desktop --diff

# Ad-hoc module test (no playbook needed)
ansible dvgs-testmachine -m apt -a "name=google-chrome-stable state=present" --become

# Start mid-playbook (skip already-verified tasks)
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-testmachine --start-at-task "install Google Chrome" --diff

# Skip known-broken tags
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-testmachine --skip-tags zoom --diff
```

Only run the full playbook as a final integration test after all individual fixes are verified.

### Log Capture

**All long-running ansible commands log to the `logs/` folder, never `/tmp`.**

- **Ansible's own structured log** is already enforced in `ansible.cfg`
  (`log_path = logs/runtime.log`) — every `ansible` / `ansible-playbook`
  invocation appends there automatically, no flags needed.
- **Redirected stdout/stderr** of a backgrounded or long deploy goes to a
  named file under `logs/`, e.g.
  `... > logs/gh16-fullrun-$(date +%y%m%d%H%M%S).log 2>&1`. Do **not**
  redirect to `/tmp` — `/tmp` is wiped on reboot (and reboot/PXE tests are
  common here), and the logs are not co-located with the run record.
- `logs/` is gitignored, so captures never reach git and persist across
  reboots for cross-session diffing.
- Grep the recap out of the log file rather than streaming full ansible
  output into the working context (`grep -E "PLAY RECAP|failed=|fatal:"`).

### Vajra headless Lua testing (1.2.2+)

Vajra ships a `vajra lua` subcommand that evaluates an arbitrary Lua chunk against the same `ctx` userdata bundled tools see. Use it to assert behavioural acceptance criteria over SSH instead of the old `strings | grep` packaging heuristics — the GTK panel is no longer required for verification.

```bash
# One-liner via -e
ansible dvgs-testmachine -m shell -a "vajra lua -e 'print(ctx.user)'"

# Multi-line script via stdin (use -)
ssh administrator@10.11.30.60 'vajra lua -' <<'LUA'
local r = ctx:run({"hostname"})
assert(r.rc == 0, "hostname failed")
io.write(r.stdout)
LUA

# Run a checked-in test file
scp utils/vajra-tests/ldap_starttls.lua administrator@dvgs-testmachine:/tmp/
ssh administrator@dvgs-testmachine 'vajra lua /tmp/ldap_starttls.lua'
```

Behaviour:

- Skips vajra's `DISPLAY` refusal — runs on a TTY-only SSH session.
- The chunk runs as a function body. `print()` writes to stdout, a returned non-nil value is rendered via `tostring()` and printed.
- Uncaught Lua errors exit non-zero with the traceback on stderr.
- Available `ctx` API mirrors the bundled tools: `ctx.user`, `ctx.uid`, `ctx.home`, `ctx.groups`, `ctx:run(argv [, opts])`, `ctx:run_privileged(...)`, `ctx:spawn(argv)`, `ctx:has(bin)`, `ctx:is_in(group)`, `ctx:is_admin()`, `ctx:config(name)`, `ctx:my_ldap_dn()`, `ctx:ldap_search(filter, attrs, base?)`, `ctx:ldap_escape(s)`.
- `ctx:run_privileged` triggers pkexec and will block waiting for an authentication agent — useless over SSH unless the host has an agent on the seat. Stick to non-privileged primitives in test playbooks; gate privileged checks behind a `host == seat` precondition.

Use this in place of `strings`-based binary inspection when verifying a vajra `.deb` deploy. Examples:

```bash
# vajra LDAP TLS / group_ou (monogarden#2, #10)
ssh administrator@dvgs-testmachine 'vajra lua -e "
  local c = ctx:config(\"ldap\")
  assert(c.group_ou:match(\"Groups\"), \"group_ou not plural: \" .. c.group_ou)
  -- StartTLS exercise: a search that would 13-error on cleartext
  ctx:ldap_search(\"(uid=*)\", {\"uid\"}, c.people_ou)
  print(\"ok\")
"'

# vajra welcome-binary safety (monogarden#12)
ssh administrator@dvgs-testmachine 'vajra lua -e "
  print(ctx:has(\"sudhanix-welcome\") and \"installed\" or \"missing\")
"'
```

Not yet shipped: `vajra tools list / status / run` (issue monogarden#5 part A). Until that lands, use `vajra lua -e` to drive the same code paths.

---

## CTTB Network Architecture

### Institutions

| Code | Name | Network |
|------|------|---------|
| DVGS | Dharma Realm Girls School | 10.11.x.x |
| DVBS | Dharma Realm Boys School | 10.11.x.x |
| DRBU | Dharma Realm Buddhist University | 10.11.x.x |

### Key Servers

| Hostname | IP | Role |
|----------|-----|------|
| srv-gw | 10.11.1.1 | Gateway, firewall, e2guardian (port 8080), squid proxy |
| pxe.cttb | 10.11.1.23 | PXE/netinstall server. Container pxe24 on srv-nas, Ubuntu 24.04 + nginx + h5ai. Cut over 2026-05-12 from the legacy Ubuntu 16.04 box; the container was re-IP'd from 10.11.13.27 into the infrastructure subnet so every downstream client (DNS, dhcp-boot on dnsmasq.cttb) reaches it at the same address the old box owned. |
| storehouse.cttb | 10.11.1.43 | Asset server (h5ai, nginx, http://storehouse.cttb/ansible) |
| wiki.cttb | 10.11.1.34 | MediaWiki 1.43.1 (container wiki-2404) — `ssh wiki` (direct, see ~/.ssh/config) |
| dns | 10.11.1.29 | Unbound DNS (authoritative for .cttb zone) |

### Network Services

- **DNS**: Unbound at 10.11.1.29, authoritative for `.cttb` domain
- **DHCP**: ISC DHCP server, assigns IPs + PXE boot options
- **Proxy**: e2guardian:8080 → squid (content filtering, timed internet access)
- **APT Mirror**: Local mirror at `apt.cttb` (Chrome, system packages)
- **NFS**: Home directories served from `fileserver` per institution
- **LDAP**: OpenLDAP for authentication, groups per institution (dvgs-students, dvgs-staff, etc.)
- **CUPS**: Per-institution print servers (cups-dvgs, cups-dvbs, etc.)
- **NTP**: Local time server
- **CA**: CTTB Root CA for internal HTTPS

### Remote Access (from Mac)

- **Direct SSH**: Works for hosts on directly reachable subnets (e.g., `ssh administrator@10.11.30.60`)
- **`ssh wiki`**: Direct — `~/.ssh/config` `Host wiki` entry reaches wiki-2404 as root with no ProxyJump needed.
- **ProxyJump `cttb`**: Tailscale subnet router on **srv-vm** (tailnet `100.125.61.66`, advertises `10.11.0.0/16`), reached as `administrator` with `~/.ssh/id_ed25519`. Moved here from rui-desktop2 (`100.121.41.88`) on 2026-06-01 — rui-desktop2 stays on the tailnet but its subnet route is disabled (one-click failover). tailscaled is the static binary + systemd unit (srv-vm is EOL 16.04, no apt repo); not yet Ansible-managed.
- **Workaround**: Use IP + `ProxyJump=none` for storehouse and other LXC hosts: `ssh -o ProxyJump=none administrator@10.11.1.43`

### Asset Distribution

All large files (fonts, themes, wallpapers, tarballs) are hosted on **storehouse.cttb** at `/srv/storehouse/ansible/`. Target machines fetch via `ansible_assets_url` (`http://storehouse.cttb/ansible`).

Deploy/update assets with:
```bash
ansible-playbook plays/deploy-assets.yml -i inventory/hosts --become
# or per group:
ansible-playbook plays/deploy-assets.yml --tags wallpapers
ansible-playbook plays/deploy-assets.yml --tags themes
```

### Desktop Role Subsystems

| File | Purpose | Tags |
|------|---------|------|
| `tasks/setup/default.yml` | Orchestrator — includes all subtask files | — |
| `tasks/lubuntu.yml` | Package installation (apt) | packages |
| `tasks/lookandfeel.yml` | Themes, fonts, panel, lightdm, greeter CSS, menu entries, xfconf | desktop, lightdm |
| `tasks/ux.yml` | Keyboard shortcuts, Thunar defaults, devilspie2, Chrome NFS lock cleanup | ux |
| `tasks/sound.yml` | ALSA, PulseAudio/PipeWire, sound theme (bigsur) | sound |
| `tasks/wallpaper.yml` | xfdesktop wallpaper rotation | wallpaper |
| `tasks/sw.yml` | Software installation (office, dev tools, Zoom) | sw_install |
| `tasks/sw-browser.yml` | Chrome (apt install + system titlebar), Firefox, Zen Browser (Flatpak) | browser |
| `tasks/sw-thunderbird.yml` | Thunderbird from Mozilla tarball + campus proxy config | thunderbird |
| `tasks/sw-vscode.yml` | VSCode (handles duplicate repo/key conflict from package) | vscode |
| `tasks/app-menu.yml` | Hide/show menu entries, NoDisplay overrides | app_menu |

### XFCE Config Templates

All deployed to `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/`:

| Template | Controls |
|----------|----------|
| `xfwm4.xml.j2` | Window manager (theme, placement, snapping, compositing) |
| `xfce4-panel.xml.j2` | Top panel (autohide, lotus icon, global menu, 24hr clock, systray) |
| `xfce4-desktop.xml.j2` | Wallpaper rotation (dir, interval, random order) |
| `xsettings.xml.j2` | GTK theme, icon theme, cursor, fonts, sound events |
| `xfce4-keyboard-shortcuts.xml.j2` | Super key → app menu, Super+Space → appfinder, Super+arrows → tiling |
| `thunar.xml.j2` | File manager defaults (list view) |
| `xfce-applications.menu.j2` | App menu layout (hostname, terminal, files, browser, categories, signoff/sleep/shutdown) |

### Other Config Files

| File | Purpose |
|------|---------|
| `lightdm-gtk-greeter.j2` | Greeter: wallpaper, WhiteSur-Dark theme, icon theme, 24hr clock |
| `lightdm.j2` | LightDM seat config (XFCE session, no guest, hide users) |
| `config/lightdm-gtk-greeter.css` | macOS-style greeter login box (dark, rounded, semi-transparent) |
| `config/clean-chrome-locks.sh` | Login script to remove stale NFS Chrome locks from other machines |
| `config/devilspie2/panel-skip-taskbar.lua` | Hide xfce4-panel from Plank dock to prevent student softlock |
| `config/terminalrc` | xfce4-terminal theme (Man Page, SeriousShanns 10pt) |
| `config/kioskrc` | Lock panel customization (sudo group only) |

### Login Autostart Scripts

Deployed to `/etc/xdg/autostart/`:

| Entry | Purpose |
|-------|---------|
| `clean-chrome-locks.desktop` | Remove stale Chrome NFS singleton locks from other hosts |
| `devilspie2.desktop` | Window rules (hide panel from Plank dock) |
| `plank.desktop` | macOS-style dock (pre-installed, not Ansible-managed) |

---

## Evaluation

- **Deploy**: `source utils/setup-env && ansible-playbook plays/cs-lab-2404.yml --limit dvgs-lab3.cttb --diff`
- **Verify**: `utils/pb util-screenshot --limit dvgs-lab3.cttb --ask-become-pass`
- **Check mode**: `ansible-playbook plays/cs-lab-2404.yml --check --diff --limit dvgs-lab3.cttb`
- **Vault password**: service `CTTB_VAULT_PASS` in the platform credential store — macOS Keychain, Windows Credential Manager, Linux Secret Service, or `~/.config/cttb/secrets/CTTB_VAULT_PASS` at mode 0600 for headless boxes. Value `<redacted>`, never committed. `ansible.cfg` wires it in via `vault_password_file = utils/vault-pass`, so no password flag is ever passed. There is no env-var fallback for this credential. Setup: `docs/sysadmin-onboarding.md`.

---

## Deployment Model

**A fleet deploy is always a destructive PXE reinstall followed by an Ansible
configuration run.** Lab hosts are never configured in place from a prior
state — the host is wiped and re-imaged via the PXE autoinstaller, then the
`install-sudhanix-cslabs.yml` play runs against the fresh OS. There is no
"upgrade a running host" path for the fleet.

**Legacy-BIOS hosts (HP 8200 Elite era) take a different stage-1 trigger.**
UEFI hosts get a one-shot `efibootmgr -n` NextBoot; BIOS firmware has no
equivalent, so the rollout (a) stamps a per-MAC `pxelinux.cfg/01-<mac>` on
pxe.cttb via `plays/sudhanix26-rollout-stage0-bios.yml` — the shared menu
deliberately times out into BootLocal, so the reimage is opt-in per MAC —
and (b) zeroes the target's whole MBR sector (boot code *and* the 0x55AA
signature; leaving the signature makes the BIOS hang in zeroed boot code
instead of falling through the boot order to the NIC). These machines also
RAM-load the install ISO (`casper url=` boot), which OOMs at 3 GB on that
hardware — they boot a stripped ~1.5 GB ISO built by
`roles/netinstall-2404/files/build-slim-iso.sh` on pxe.cttb (casper layers +
apt metadata, minus HWE/restricted/firmware payloads). Remove the per-MAC
files after the reinstall (`-e bios_rollout_state=absent`): while present,
any PXE boot of that MAC reimages the machine.

**UEFI hosts (DVGS Dell Inspiron 24 5000 fleet) need Secure Boot toggled off
for the netboot itself.** dnsmasq sends UEFI clients straight to
`grubx64.efi` — deliberately no shim hop, because shim 15.8 (the only version
in any Ubuntu archive) mis-derives its netboot second stage on this Dell
firmware and dies on a garbage TFTP fetch (rhboot/shim#696; symptom is
`Fetching Netboot Image <?>Onboard` … `start_image() returned TFTP Error`).
Canonical-signed GRUB won't launch directly under Secure Boot, so the
per-machine procedure is: Secure Boot **off** → PXE install → Secure Boot
**back on**. The bug is netboot-only; the installed system boots through its
on-disk shim normally, so nothing is permanently weakened. Do not point
dnsmasq back at `shimx64.efi` before verifying a fixed shim on a real Dell.

**Consequence — the forward-only Recommends caveat does not apply to the
fleet.** Because every fleet host is a fresh image at deploy time, it always
receives the full Recommends closure (path A in the gh-16 plan *is* the
rollout — there is no path B for the fleet). The "Ansible doesn't backfill
Recommends onto already-installed packages" nuance only matters for
**long-lived ad-hoc targets** that are re-run without reimaging — i.e.
`dvgs-testmachine` during development, not production lab hosts. Treat it as
a testbench artifact, not a rollout risk.

---

## Software Distribution Policy

Campus firewall (`srv-gw`, firehol) **rejects all outbound HTTPS** from student/lab IP groups. Snap store, PPAs, and external HTTPS repos are unreachable from lab machines. The `apt.cttb` debmirror container (10.11.1.22) has unrestricted internet (in `no_proxy` ipset) and syncs upstream repos.

**Policy: no snaps, no PPAs. Use local mirrors, tarballs, or Flatpak.**

**Recommends are now ENABLED for the lab-desktop apt batches** (`roles/sudhanix-core` `lubuntu`/`sw`/`lang`/`sw-office`). Rationale: a hand-curated `install_recommends: no` list silently drops transitive desktop integration (this is how gh-76 lost `accountsservice` and gh-78 lost `canberra-gtk-play`; audio firmware was similarly at risk), and the ops team is too transient to maintain that closure by hand. The no-snap collision is closed by a negative APT pin (`roles/sudhanix-core/files/cttb-no-snap.pref` → `/etc/apt/preferences.d/`, pinning `snapd`/`gnome-software-plugin-snap`/`firefox`/`thunderbird` to Priority -1), deployed *before* the first recommends batch so Recommends can never reintroduce snap machinery. Server/base roles (`common`, infra) deliberately stay `install_recommends: no` — minimal footprint, no desktop-integration need.

| Software | Method | Source |
|----------|--------|--------|
| System packages | apt | `apt.cttb` (local debmirror of archive.ubuntu.com) |
| Chrome | apt | `apt.cttb/mirrors/chrome` (local mirror of dl.google.com) |
| Firefox | tarball | `storehouse.cttb/ansible/firefox-latest.tar.xz` (Mozilla; apt `firefox` is a snap-transitional stub on noble — pinned -1) |
| Thunderbird | tarball | `storehouse.cttb/ansible/thunderbird-*.tar.bz2` |
| Zen Browser | Flatpak | Flathub (`io.github.zen_browser.zen`) |
| VSCode | apt | Direct from `packages.microsoft.com` (HTTPS, works via proxy) |
| Fonts/themes | tarball | `storehouse.cttb/ansible/` |
| Zoom | .deb | `storehouse.cttb/ansible/zoom_amd64.deb` |

Snap store is removed on all lab machines (`snap: name=snap-store state=absent`). Thunderbird's snap transition package is also removed. With Recommends now enabled, the `cttb-no-snap.pref` APT pin is the authoritative guard that keeps `snapd` and snap-transitional browser stubs from being reintroduced.

---

## Known Issues & Workarounds
- **Chrome NFS lock** — Chrome locks its profile via symlink (`SingletonLock → hostname-pid`). On NFS homes, a crash/reboot on one machine blocks Chrome on all others. Fixed with login cleanup script (`clean-chrome-locks.sh`).
- **VSCode repo conflict** — the `code` package auto-creates `vscode.sources` (deb822 format with `microsoft.gpg`) which conflicts with our `vscode.list` (using `microsoft.asc`). The role removes both the stale `.sources` and `.gpg` after install.
- **Chrome .desktop filename** — the package installs `google-chrome.desktop` (not `google-chrome-stable.desktop`).
- **Zoom .deb signature** — `zoom_amd64.deb` on storehouse has an invalid archive signature. Zoom itself is pre-installed; upgrade task fails. Skip with `--skip-tags zoom`.
- **Plank dock** shows xfce4-panel wrapper windows. Fixed with devilspie2 `skip_tasklist` rule, but needs login verification.
- **devilspie2 rules** live in `/etc/xdg/devilspie2/` — add `.lua` files for window behavior overrides.
- **xfdesktop 4.18+** (Ubuntu 24.04) uses `backdrop-cycle-*` property names, not the older `image-show`/`image-period`.
- **Monitor property** in xfce4-desktop.xml must match xrandr output name (e.g., `monitorHDMI-1` for Dell AIOs).
- **Greeter CSS** loaded via `@import` in WhiteSur-Dark's `gtk.css`. The `theme-name = WhiteSur-Dark` setting in greeter conf is required.
- **PulseAudio system service** only for Ubuntu < 24.04. Ubuntu 24.04+ uses PipeWire per-user.
