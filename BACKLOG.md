# Backlog: Ubuntu 24.04 Upgrade

Consolidated from dvgs-lab3/dvgs-testmachine test deployment. Must resolve before mass rollout.

---

## Blockers

- [ ] **Autoinstall not triggering on PXE boot** — cloud-init doesn't fetch user-data from network URL. Templates updated with `ds="nocloud-net;s=URL"` + `cloud-config-url=URL` (2026-04-23) but not yet deployed/tested on PXE server.
- [ ] **Firefox snap blocks on campus** — Ubuntu 24.04 `firefox` apt is a snap wrapper; snap store unreachable. Options: (a) Mozilla tarball like Thunderbird, (b) chromium-browser .deb, (c) wait for PPA/firewall fix.

---

## Must Fix (before rollout)

- [ ] **Deploy autoinstall fix to PXE server** — rsync rendered GRUB line with `ds="nocloud-net;s=URL"` + `cloud-config-url=` to `/srv/netinstall/boot/grub/grub.cfg`
- [ ] **Codify UEFI GRUB in netinstall-2404 role** — grub.cfg template + `grubnetx64.efi` deployment task (currently manual on PXE server)
- [ ] **Verify noble apt.cttb sync** — sync started 2026-04-30. Check completion, test `apt update` without `deb_mirror` override
- [ ] **Verify services on dvgs-testmachine** — CUPS, LDAP auth, NFS mounts, CA certs, desktop theme
- [ ] **`desktop_login_background` var missing from dvbs/drbu group_vars** — only dvgs has the new variable; other sites will get wrong background
- [ ] **Revert dvgs-testmachine unrestricted filter** — remove `10.11.9.23` from `adult` e2guardian group in `host_vars/srv-gw` (added for testing)
- [ ] **dvgs-testmachine unreachable after reboot** — host not responding via SSH. Needs physical console check (stuck at DM, DHCP change, or boot issue)

---

## Should Fix

- [ ] **USB autoinstall path** — `optional: true` added to wifi templates, but need a reliable USB drive (59GB Flash Disk has flaky I/O causing SQUASHFS corruption)
- [ ] **WhiteSur theme visual verification** — GTK/icons/cursors installed and configured, needs login to verify rendering
- [ ] **Roll out to remaining lab hosts** — DVGS (lab1-9 excluding testmachine), DVBS, DRBU

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
- [x] ~~apt.cttb mirror missing Noble~~ — sync started 2026-04-30
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
