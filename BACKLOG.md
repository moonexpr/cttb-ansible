# Backlog: Ubuntu 24.04 Upgrade

Consolidated from dvgs-lab3/dvgs-testmachine test deployment. Must resolve before mass rollout.

---

## Blockers

- [ ] **Autoinstall not triggering on PXE boot** — cloud-init doesn't fetch user-data from network URL. Templates updated with `ds="nocloud-net;s=URL"` + `cloud-config-url=URL` (2026-04-23) but not yet deployed/tested on PXE server.

---

## Must Fix (before rollout)

- [ ] **Deploy autoinstall fix to PXE server** — rsync rendered GRUB line with `ds="nocloud-net;s=URL"` + `cloud-config-url=` to `/srv/netinstall/boot/grub/grub.cfg`
- [ ] **Codify UEFI GRUB in netinstall-2404 role** — grub.cfg template + `grubnetx64.efi` deployment task (currently manual on PXE server)
- [ ] **LDAP auth — TLS handshake failure** — nscd running, `do_start_tls failed` in logs. LDAP server at ldap.cttb (10.11.1.25) reachable on port 389, port 636 refused. PAM/NSS config correct. Fix requires either: (a) fix TLS on LDAP server, (b) set `ssl off` + `tls_checkpeer no` in `/etc/ldap.conf`, or (c) install nslcd as alternative. 439 local users resolve, 0 LDAP users.
- [ ] **Upload fresh Zoom .deb to storehouse** — storehouse copy is corrupted (4.3KB HTML error page, not a .deb). Fresh 281MB .deb downloaded from zoom.us to `/tmp/zoom_new.deb` on testmachine. Copy it to storehouse `/srv/ansible/zoom_amd64.deb`.
- [ ] **New greeter avatars for the schools** — something relatable, down to earth, and visually consistent across different schools.
- [ ] **devilspie2 not starting** — XFCE session and Plank run on login, but devilspie2 absent from process list. Desktop shows black via remote screenshot. Check autostart file and Lua script syntax.
- [ ] **Full clean playbook run** — run with `--skip-tags zoom` and confirm zero failures

---

## Should Fix

- [ ] **USB autoinstall path** — `optional: true` added to wifi templates, but need a reliable USB drive (59GB Flash Disk has flaky I/O causing SQUASHFS corruption)
- [x] ~~Test devilspie2 panel fix~~ — tested via remote login: devilspie2 not starting. Moved to Must Fix (2026-05-04)
- [ ] **Verify greeter CSS on physical monitor** — remote screenshot shows dark rounded login box but low-res; verify appearance at the machine
- [ ] **Fix SSH ProxyJump via Tailscale** — `cttb` jump host (100.121.41.88) works for SSH but key auth for `johnchandara` is intermittent. Not codified in inventory (handled by local SSH config).
- [ ] **Roll out to remaining lab hosts** — DVGS (lab1-9 excluding testmachine), DVBS, DRBU

---

## Sudhanix OS Branding (remove Ubuntu references)

User-facing strings still say "Ubuntu" in many places. Goal: anywhere a non-admin user sees the OS name, it should say Sudhanix. Internal `ID_LIKE=ubuntu` and apt repo URLs stay (technical compat, not user-visible).

### Done (2026-05-05)
- [x] **`/etc/lsb-release`** — `DISTRIB_ID=sudhanix`, `Sudhanix 26`, codename `storehouse` via `roles/common/templates/lsb-release.j2`
- [x] **`/etc/os-release`** — `PRETTY_NAME="Sudhanix 26"`, `NAME=Sudhanix`, HOME_URL→wiki.cttb via `roles/common/templates/os-release.j2`
- [x] **MOTD `/etc/update-motd.d/00-header`** — wiki.cttb primary, Ubuntu/XFCE secondary
- [x] **Disable Ubuntu MOTD scripts** — chmod -x on `10-help-text`, `50-motd-news`, `90-updates-available`, `91-release-upgrade`, `95-hwe-eol`

### Must Fix
- [ ] **Persist `/etc/os-release` against `base-files` upgrades** — currently overwritten on apt upgrade. Use `dpkg-divert --rename --add /etc/os-release` before deploying template, or a daily cron/systemd-timer that re-applies the template
- [ ] **GRUB menu strings** — `/boot/grub/grub.cfg` shows "Ubuntu, with Linux ...". Override via `GRUB_DISTRIBUTOR="Sudhanix"` in `/etc/default/grub` (already templatable in `roles/server/files/default-grub`), then `update-grub`
- [ ] **GRUB theme** — currently default Ubuntu purple. Build/deploy a Sudhanix-branded theme (logo + colors) at `/boot/grub/themes/sudhanix/` and reference in `/etc/default/grub`
- [ ] **Plymouth boot splash** — replace `ubuntu-logo` plymouth theme with a Sudhanix theme. Asset: `sudhanix-plymouth.tar.gz` on storehouse → `/usr/share/plymouth/themes/sudhanix/`. Run `update-alternatives --set default.plymouth ...` then `update-initramfs -u`
- [ ] **LightDM greeter banner/title** — currently shows "Ubuntu" via `lightdm-gtk-greeter` defaults. Set `indicators=...` and any visible string in `lightdm-gtk-greeter.j2` to Sudhanix branding. Logo asset already in role
- [ ] **About-this-system in XFCE settings panel** — `xfce4-about` reads from `/etc/os-release` (covered by os-release.j2)
- [ ] **`lsb_release -a` codename fallback** — verify on first deploy that it doesn't fall back to `/usr/share/distro-info/ubuntu.csv`. If it does, also override that file

### Should Fix
- [ ] **Issue files** — `/etc/issue` and `/etc/issue.net` still say `Ubuntu 24.04.X LTS \n \l`. Templatize with Sudhanix string. Visible at TTY login prompt
- [ ] **Hostname/welcome message in shells** — any custom `/etc/profile.d/*.sh` or `/etc/skel/.bashrc` that emits "Welcome to Ubuntu". `bashrc` in `roles/common/files/conf/bashrc` should be reviewed
- [ ] **Firefox/Chrome about: pages** — out of our control, but the OS string they probe (e.g. about:support → "OS: ...") will read from `/etc/os-release` (covered)
- [ ] **Settings → System Info dialogs** — gnome-control-center / xfce4-about all read os-release. Verify after deploy
- [ ] **Login banner SSH (`/etc/issue.net`)** — visible before authentication if `Banner` directive set in sshd_config. Currently not set; consider setting to a Sudhanix banner for SSH brand consistency
- [ ] **`/etc/legal`** — Ubuntu's "the programs included with the Ubuntu system" notice. Replace or remove
- [x] ~~Ansible role rename~~ — `desktop` → `sudhanix-core`, `desktop-distributed` → `sudhanix-distributed`, `ux.yml` → `sudhanix-ux.yml`. Tags renamed in lockstep (2026-05-05)
- [ ] **Playbook rename** — `cs-lab-2404.yml` → `cs-lab-sudhanix.yml` (still has Ubuntu version in name)
- [ ] **`UPDATE_JOURNAL.md` heading** — currently "Ubuntu 24.04 Upgrade." Rename to "Sudhanix OS 26 Migration" once project transitions from upgrade-mode to maintenance-mode

### Nice to Have
- [ ] **Sudhanix-branded autoinstall ISO** — bake current Ansible state into a bootable installer via `cubic` or `livecd-rootfs`. Single artifact: `sudhanix-26-amd64.iso`. Replaces the user-data-over-PXE pipeline for offline installs and gives a clean handoff story
- [ ] **Sudhanix wallpaper set** — campus-photographed wallpapers (CTTB grounds, gardens, statues) replacing/supplementing the current macOS Big Sur set
- [ ] **First-boot welcome wizard** — small Tk/Python or zenity script run once via systemd to show a "Welcome to Sudhanix" intro pointing to wiki.cttb. Optional, only if user-onboarding becomes important
- [ ] **VM testing pipeline** — Vagrant/multipass + the Ansible role for pre-deploy validation. Doesn't require a fork; just a `Vagrantfile` and a small docs page

---

## Nice to Have

- [ ] **Add noble-backports + debian-installer sections to debmirror** — initial sync is main/restricted/universe/multiverse only. Add once base sync completes and PXE needs d-i packages
- [ ] **Trim debmirror: drop xenial** — EOL. Check if any machines still need it, then remove
- [ ] **Evaluate Ubuntu 26.04 LTS** — released April 2026. Ansible fixes use `>= 24` guards so they carry forward. Wait for 26.04.1 (~July 2026), then swap ISO + debmirror entry and re-test
- [ ] **Clone `ansible-new` from git.cttb** — compare with local repo to identify drift
- [ ] **Fix gitolite hooks** — Perl `@INC` missing gitolite lib; `update` hook broken on push
- [ ] **Investigate mon container** — running on srv-vm but no monitoring daemon detected
- [ ] **Investigate metrics container** — stopped on srv-nas, may be decommissioned

---

## Completed

- [x] ~~Autoinstall hostname~~ — fixed 2026-04-30 (common role `ansible.builtin.hostname` task)
- [x] ~~apt.cttb mirror missing Noble~~ — sync started 2026-04-30, verified working 2026-05-04 (noble, noble-security, noble-backports all present)
- [x] ~~Chrome GPG key expired~~ — fixed 2026-04-30 (trustedkeys.gpg updated, mirror re-synced)
- [x] ~~No HTTPS egress from campus LAN~~ — root cause: e2guardian `timed_internet.sh` cron schedule
- [x] ~~All playbook failures~~ — resolved run 17 (ok=144, changed=27, failed=0)
- [x] ~~LDAP nsswitch.conf version guard~~ — removed `== '20.04'` guard
- [x] ~~LightDM not set as default DM~~ — task added to write `/etc/X11/default-display-manager`
- [x] ~~IPv6 disable sysctl~~ — config deployed, applies on reboot
- [x] ~~Wallpaper rotation~~ — replaced cron+feh with xfdesktop native cycling (2026-05-01)
- [x] ~~Desktop icon text shadow~~ — `show-icon-label-shadows` + Semi-Bold font (2026-05-01)
- [x] ~~WhiteSur tarballs uploaded~~ — 2026-04-22
- [x] ~~WiFi on dvgs-lab3~~ — connected to DRBU via nmcli (2026-04-30)
- [x] ~~dvgs-testmachine unreachable after reboot~~ — actual IP is 10.11.30.60 (not 10.11.9.23); reachable via direct SSH (2026-05-04)
- [x] ~~Thunderbird internet connectivity~~ — campus proxy (10.11.1.1:8080) not configured; deployed autoconfig pref (2026-05-04)
- [x] ~~Window snapping~~ — already in xfwm4.xml.j2: snap_to_border/windows (2026-05-04)
- [x] ~~Center window spawn~~ — already in xfwm4.xml.j2: placement_mode=center (2026-05-04)
- [x] ~~Terminal font size~~ — 12→10pt in terminalrc (2026-05-04)
- [x] ~~Log Out menu entry~~ — cttb-signoff.desktop above Sleep/Shutdown (2026-05-04)
- [x] ~~Thunar list view~~ — thunar.xml.j2 with ThunarDetailsView default (2026-05-04)
- [x] ~~Meta key → app menu~~ — xfce4-keyboard-shortcuts.xml.j2 (2026-05-04)
- [x] ~~Application search~~ — xfce4-appfinder + Super+Space shortcut (2026-05-04)
- [x] ~~Greeter wallpaper~~ — lightdm points to Big-Sur-Day.jpg; directory paths don't work (2026-05-04)
- [x] ~~Dark theme icons~~ — switched icon_theme to WhiteSur-dark (2026-05-04)
- [x] ~~System sounds~~ — bigsur theme installed from storehouse, enabled in xsettings (2026-05-04)
- [x] ~~Chrome default browser~~ — xdg-settings in sw-browser.yml (2026-05-04)
- [x] ~~Wallpaper archive updated~~ — rebuilt and uploaded to storehouse (208MB, 2026-05-04)
- [x] ~~Panel in Plank dock~~ — devilspie2 with skip_tasklist rule (2026-05-04)
- [x] ~~Remote screenshot utility~~ — plays/util-screenshot.yml (2026-05-04)
- [x] ~~Fonts/assets to storehouse~~ — already done, all assets use ansible_assets_url (2026-05-04)
- [x] ~~Chrome not installed~~ — added apt install task, fixed .desktop filename to `google-chrome.desktop` (2026-05-04)
- [x] ~~Chrome NFS lock~~ — login script removes stale SingletonLock from other hostnames (2026-05-04)
- [x] ~~Log Out menu duplicate~~ — excluded system `xfce4-session-logout.desktop` from top-level menu (2026-05-04)
- [x] ~~24hr clock~~ — changed panel clock to `%H:%M` format (2026-05-04)
- [x] ~~VSCode repo conflict~~ — cleanup tasks for auto-generated `vscode.sources` + stale `.gpg` key (2026-05-04)
- [x] ~~Greeter black background~~ — lightdm-gtk-greeter needs file path not directory; pointed to Big-Sur-Day.jpg (2026-05-04)
- [x] ~~Greeter [language_code]~~ — removed `~language` indicator (2026-05-04)
- [x] ~~Greeter macOS styling~~ — WhiteSur-Dark theme + custom CSS with dark rounded login box (2026-05-04)
- [x] ~~Zen Browser installed~~ — Flatpak from Flathub, confirmed working (2026-05-04)
- [x] ~~Firefox installed~~ — apt package with install_recommends: no (2026-05-04)
- [x] ~~Firefox snap blocker~~ — resolved: apt .deb, not snap wrapper. Snap-store removed (2026-05-04)
- [x] ~~Revert dvgs-testmachine unrestricted filter~~ — removed stale 10.11.9.23 from `adult` group in host_vars/srv-gw, set ips to `[]` (2026-05-04)
- [x] ~~Per-site wallpapers~~ — unified to Big-Sur-Day.jpg across all sites (dvgs, dvbs, drbu). No per-school backgrounds needed (2026-05-04)
- [x] ~~Verify wallpapers deployed~~ — Big-Sur-Day.jpg (10.8MB) in `/usr/share/backgrounds/cttb/`, 35 wallpapers total, tarball on storehouse (2026-05-04)
- [x] ~~Zoom .deb diagnosed~~ — storehouse copy corrupted (4.3KB HTML error). Fresh download from zoom.us works (281MB valid .deb). Campus firewall not blocking zoom.us (2026-05-04)
- [x] ~~Thunderbird proxy~~ — campus proxy autoconfig pref deployed (2026-05-04)
- [x] ~~Verify noble apt.cttb sync~~ — noble, noble-security, noble-backports all present on apt.cttb (2026-05-04)
- [x] ~~Verify WhiteSur-dark icon archive~~ — `/usr/share/icons/WhiteSur-dark` exists on testmachine (2026-05-04)
- [x] ~~Source macOS sound theme~~ — bigsur theme tarball on storehouse (614KB), installed to `/usr/share/sounds/bigsur` (2026-05-04)
- [x] ~~CUPS running~~ — `lpstat -r` confirms scheduler running on testmachine (2026-05-04)
- [x] ~~NFS mounts~~ — autofs mounted at `/nfs/home` on testmachine (2026-05-04)
- [x] ~~CA certs~~ — CTTB Root CA at `/usr/local/share/ca-certificates/CTTB-Root-CA.crt`, symlinked in `/etc/ssl/certs/` (2026-05-04)
