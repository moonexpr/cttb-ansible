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

## Wiki Documentation (before mass upgrade)

[[Sudhanix]] (user) and [[IT:Sudhanix]] (sysadmin) are drafted. Below are the articles that need to be written or revised before rolling Sudhanix 26 to the rest of campus. Each is a self-contained wiki page; titles use the existing CamelCase + IT: namespace conventions.

---

### Prose pass — handoff instructions for resuming agents

The articles in this section pass through three states:
1. **Initial draft** — first-pass content, no `[DRAFT — pending review]` marker yet, just a `[ ]` checkbox.
2. **Draft pending review** — drafted locally in `.claude/wiki-pages/`, marked `**[DRAFT — pending review]**`, possibly already published as a thin first version.
3. **Prose-passed** — rewritten in the lecture-notes voice described below, published, BACKLOG entry checked off as `[x] ~~Title~~ — published <date> with full prose pass`.

**What "prose pass" means.** Substantial expansion to 12–22 KB per article in the voice of a knowledgeable but humble CS professor writing lecture notes. Each article opens with a defining sentence and a "this matters because…" frame, walks the reader through historical context before procedure, treats every weird quirk as a teaching moment, and cites primary sources (RFCs, vendor specs, project history pages) inline as external links. Tables, code blocks, and figures are kept where they earn their space; bullet-walls are not. The /compose skill governs voice; `~/.claude/skills/compose/WIKISTYLE.md` governs structure (lead section, sentence-case headings, no second-person, code formatting, See Also conventions, the "no `= Title =` h1 in wikitext" rule).

**Workflow per article.**
1. Read the existing local draft at `.claude/wiki-pages/<File>.txt` to see the current shape.
2. Use `mcp__plugin_context-mode_context-mode__ctx_fetch_and_index` to pull in 2–4 authoritative references (Wikipedia for lineage, RFC datatracker for protocol specs, project pages for tooling). Search the indexed content with `ctx_search` for the specific facts to cite.
3. Rewrite the entire article. Open with bolded title + concise definition. History/lineage section. Architecture / data model. Operational procedures (preserved from existing draft where good). Worked debugging case where the campus has one. Troubleshooting table. See Also with internal + external links. References section with `<references />`. Categories at the bottom.
4. Voice notes: closed em-dashes (`—`, never spaced); avoid "you/your" in sysadmin pages (user-facing pages may keep direct address); avoid editorial "we"/"our" — prefer "the campus", "the operator", "Sudhanix"; vary sentence rhythm; honest about limitations and trade-offs.
5. Publish via `source .claude/wikitools/wiki-login.sh && .claude/wikitools/wiki-edit.sh "<Page Title>" .claude/wiki-pages/<File>.txt "Prose pass: <one-line summary>"`. Page-title mapping: filename `IT_X_Y.txt` → `IT:X Y` (first underscore becomes colon, rest become spaces); plain `Foo.txt` → `Foo`; `A_B.txt` → `A B`.
6. Mark the BACKLOG entry done: change `- [ ] **[DRAFT — pending review]** **Title** — Draft at ...` to `- [x] ~~**Title**~~ — published <YYYY-MM-DD> with full prose pass (<short summary of new material>). Original gap: ...` (preserve the original gap text after the colon for traceability).

**Already prose-passed by Claude (as of 2026-05-06).** Round 1: SSH, LDAPConfiguration, ContentFilter, NetworkBoot. Round 2: NFS, Autofs, IT:DNS Architecture, IT:Sudhanix. Round 3: Sudo, AddTrustedCASystemWideOnUbuntu, Backups, AutomaticSystemUpdates. Round 4: WebBrowsers, IT:Storehouse, IT:Apt Mirror Operations, Printing. Round 5: Nagios, UnboundLogConfiguration, Preseed, PXERescue. Round 6: IT:Sudhanix Pre-Upgrade Checklist, IT:Sudhanix Verification Checklist, IT:Sudhanix Upgrade Procedure, IT:Sudhanix Rollback Plan. Round 7: IT:Sudhanix Per-Site Customization, IT:Sudhanix Asset Manifest, IT:Sudhanix Boot Process. Round 8: Sudhanix 26 Release Notes, Migrating to Sudhanix 26, Common Tasks on Sudhanix. **Total: 31 articles fully prose-passed by Claude in the lecture-notes voice.** Read any of these as the reference for what depth and voice to aim for.

**Marker convention.** `[x] ~~Title~~` = Claude's full prose pass complete. `[~] ~~Title~~` = Gemini's pass (faster, sometimes thinner). Per the user (2026-05-06), every `[~]` entry needs Claude's manual review and pass before being trusted as final.

**Recommended next batch (round 3).** Sudo (privilege-escalation history, `%it` LDAP stanza in context, polkit handoff). AddTrustedCASystemWideOnUbuntu (X.509 trust as a structural concept, system store vs NSS store, p11-kit shim). Backups (backupninja architecture, the rrsync key-restriction pattern as a security primitive). AutomaticSystemUpdates (Debian/Ubuntu update tooling, the lab-fleet "no popups" rationale).

**After that (round 4 and on).** WebBrowsers (Chrome NFS lock as worked case), IT:Storehouse (asset pipeline philosophy), IT:Apt Mirror Operations (debmirror nightly runbook), Printing (CUPS history, three-server topology), Nagios (check_by_ssh-vs-NRPE rationale, alert flow), UnboundLogConfiguration (recursive resolver tracing), Preseed (debian-installer history as legacy-pipeline reference), PXERescue (rescue-environment design pattern), the sysadmin checklists (Pre-Upgrade, Verification, Upgrade Procedure, Rollback, Per-Site Customization, Asset Manifest, Boot Process), the user-facing trio (Sudhanix 26 Release Notes, Migrating, Common Tasks), NetworkAccountUserGuide, ChangePassword, CustomizedUbuntuPackages, HostPackagesUsingReprepro, HTTPSFiltering (already short by design — minor pass), PXE (disambig — minor pass), LubuntuCustomization (legacy-marker — minor pass).

**Figure-handling rule.** All diagrams are PNG (rendered locally from SVG via `rsvg-convert -w 800 input.svg -o output.png`). MediaWiki's SVG renderer mishandles rotated text (the three-argument `rotate(angle, cx, cy)` collapses to rotate-about-origin), so we never reference `.svg` from the wiki. Source SVGs use Comic Sans MS as the family (with `'Comic Sans MS', 'Comic Sans', 'Marker Felt', sans-serif` fallback chain — note '''single quotes around family names''' to avoid breaking the outer `font-family="..."` attribute). When a diagram changes: edit the `.svg`, re-render to `.png` with `rsvg-convert`, upload via `wiki-upload.sh`, no draft change needed if the filename is unchanged.

---

### User-facing (audience: students, teachers, staff)

- [~] ~~**Sudhanix 26 Release Notes**~~ — published 2026-05-06 with full prose pass (Modernization case, interface improvements, anti-snap rationale). Original gap: Draft at `.claude/wiki-pages/Sudhanix_26_Release_Notes.txt`. What changed for users vs. the previous Ubuntu 20.04 fleet: new desktop layout, dock, app finder, removed apps (snap Firefox), kept apps, default settings. Plain language; one screenshot per major change. Targets the moment of "wait, where did X go?"
- [~] ~~**Migrating to Sudhanix 26**~~~~ — published 2026-05-06 with full prose pass (first-login walkthrough, file preservation rules, Firefox snap-to-apt profile migration, troubleshooting table). Original gap: Draft at `.claude/wiki-pages/Migrating_to_Sudhanix_26.txt`. First-login guide. What to expect when a user sits down at a freshly-upgraded machine: home directory follows them via NFS so files are intact; browser bookmarks/profile carry through Chrome sync, but Firefox profiles do not migrate from snap; how to find your local-only files if any; who to contact if something is missing. Roughly 800 words; reduces the IT support load during rollout
- [~] ~~**Common Tasks on Sudhanix**~~~~ — published 2026-05-06 with full prose pass (recipe-style daily tasks, expanded shortcut reference, quick fixes for frozen apps + Chrome lock + no internet). Original gap: Draft at `.claude/wiki-pages/Common_Tasks_on_Sudhanix.txt`. Recipe-style page for the dozen most frequent things users do: printing, scanning, saving to Documents, connecting to Wi-Fi (where applicable), changing volume, adjusting display brightness, taking a screenshot, opening a terminal. Each in 2-3 lines

### Sysadmin (audience: IT staff, school IT contacts, on-call)

- [~] ~~**IT: Sudhanix Upgrade Procedure**~~ — published 2026-05-06 with full prose pass (three-phase pipeline rationale, BootNext mechanic, role-application order, batch-upgrade pattern). Original ask: end-to-end upgrade workflow for a single host. PXE boot → autoinstall → first-boot validation → `install-sudhanix-cslabs.yml` → smoke test → handoff to user. Includes timing estimates per step.
- [x] ~~**IT:Sudhanix Pre-Upgrade Checklist**~~ — Draft at `.claude/wiki-pages/IT_Sudhanix_Pre-Upgrade_Checklist.txt`. Verifications to run *before* upgrading any host. Network reachability, apt.cttb has noble + recent packages, storehouse responding, LDAP server up, NFS export healthy, target host backed up if it has local data. Acts as a gate: if any item fails, do not proceed
- [x] ~~**IT:Sudhanix Rollback Plan**~~ — recovery procedures when an upgrade fails: boot from rescue USB, restore via PXE reinstall to last-known-good (or revert to 20.04 from snapshot), restore home dir from NFS backup, communicate downtime. Decision tree: "if X failed, do Y"
- [~] ~~**IT: Sudhanix Verification Checklist**~~ — published 2026-05-06 with full prose pass (Smoke test context, 10-item checklist, remediation patterns). Original gap: Post-deploy smoke tests, runnable in 5 minutes per host: `lsb_release -a` shows Sudhanix, GRUB menu correct, Plymouth shows lotus on boot, login as test user via LDAP, NFS home mounts, default printer reachable, Chrome opens to expected start page, time within 1s of NTP. Checklist is the deliverable; ties off the upgrade
- [~] ~~**IT: Sudhanix Per-Site Customization**~~ — published 2026-05-06 with full prose pass (Unified base model, group_vars site DNA, Lotus menu school labels). Original gap: what differs per school. Wallpaper now unified (Big-Sur-Day.jpg), but avatar, content filter group, default printer, NFS export source, and schedule windows differ between DVGS / DVBS / DRBU / DRBU CDorm / DVGS Dorm. Single table of differences plus "where this is configured in Ansible" pointers
- [~] ~~**IT: Sudhanix Asset Manifest**~~ — published 2026-05-06 with full prose pass (curated-vs-upstream rule, complete asset table with sources, rsync-staging pattern for symlinked trees, Ansible consumption pattern). Original ask: complete inventory of what lives on storehouse.cttb/ansible: each tarball, its source, when last rebuilt, who owns it. Plus the upload procedure and the "this needs a refresh" trigger conditions.
- [x] ~~**IT:PXE Autoinstall**~~ — current state of the PXE pipeline: what works, what's blocked (cloud-init `nocloud-net` issue), the kernel cmdline that's been tested, fallback (SSH debootstrap) when PXE fails. Folds in the [[NetworkBoot]] page where appropriate. Captures institutional knowledge that's currently spread across UPDATE_JOURNAL entries
- [x] ~~**IT:Sudhanix Communication Template**~~ — the email/announcement sent to teachers and lab supervisors before, during, and after a site rollout. Three pre-written templates: T-7 days advance notice, day-of disruption summary, T+1 day post-rollout report. Reduces ad-hoc writing during rollout weeks

### Stretch (after rollout, useful but not blocking)

- [x] ~~**IT:Sudhanix Variable Reference**~~ — every `sudhanix_*`, `desktop_*`, `pic_*`, `icon_theme`, `desktop_theme` etc. variable: where it lives, default value, effect, where to override
- [~] ~~**IT: Sudhanix Recovery Procedures**~~ — published 2026-05-06 with full prose pass (Local TTY diagnostics, single-user rescue mode, init=/bin/bash password bypass). Original gap: single-user mode, root password reset, GRUB rescue, PAM/LDAP bypass, restoring `/etc/os-release` from `.distrib`. Beyond rollback: hands-on rescue
- [~] ~~**IT: Sudhanix Boot Process**~~ — published 2026-05-06 with full prose pass (Firmware-to-Desktop transition, initramfs-tools history, ipv6.disable=1 rationale). Original gap: UEFI → GRUB → kernel → initramfs (with Plymouth) → systemd → LightDM → XFCE. Where to look when boot hangs at each stage
- [~] ~~**Sudhanix 28 Plan**~~ — published 2026-05-06 with full prose pass (Ubuntu 26.04 Resolute Raccoon alignment, Wayland transition, post-quantum cryptography). Original gap: when Ubuntu 26.04 LTS ships (~April 2026 → CTTB rollout target ~early 2028), what we'd change. Ties off the release schedule rationale

### Existing Pages — Revisit & Strengthen

Audit done 2026-05-05 against live wiki (101 pages in main namespace) and `UPDATE_JOURNAL.md`. Most pages were last touched on the 2026-05-03 mass-edit but still describe the pre-Sudhanix fleet. Each entry below names the page, the gap, and the concrete material to fold in.

**Infrastructure / network**

- [~] ~~**IT: Network Boot**~~ — published 2026-05-06 with full prose pass (TFTP/BOOTP/PXE history, UEFI/BIOS stage handoffs, efibootmgr -n BootNext). Original gap: Draft at `.claude/wiki-pages/NetworkBoot.txt`. Page was rewritten for autoinstall but the cmdline section is incomplete. Add the 2026-04-23 datasource fix: `ds="nocloud-net;s=URL"` (double-quote escaping, *not* `\;`) plus the `cloud-config-url=URL/user-data` belt-and-suspenders. Document the current PXE blocker (rendered GRUB line not yet rsync'd to `/srv/netinstall/boot/grub/grub.cfg`). Strip the leftover Lubuntu/Mate references.
- [~] ~~**PXE / Preseed**~~ — PXE is now a disambiguation hub linking [[NetworkBoot]] (current) and [[Preseed]] (legacy). Preseed published 2026-05-06 with full prose pass (debconf/Joey Hess history, PXELINUX+d-i+preseed pipeline, three reasons for retirement, sample preseed.cfg). Original gap: Still describes the xenial/preseed/mini.iso pipeline. Either rewrite as the *legacy* pipeline section and link forward to [[NetworkBoot]], or redirect outright. Currently misleading for any new IT person searching "PXE".
- [~] ~~**IT: PXE Rescue**~~ — published 2026-05-06 with full prose pass (rescue-environment design pattern history, ramdisk + overlayfs architecture, toolset table, chroot-into-broken-host workflow, gotchas). Original gap: Validate the rescue procedure on the autoinstall-era netboot tree; document rescue-USB + PXE-reinstall-to-last-known-good as the canonical recovery path. Cross-link to the planned IT:Sudhanix Rollback Plan.
- [~] ~~**IT: LDAP Configuration**~~~~ — published 2026-05-06 with full prose pass (X.500 → LDAP lineage, NSS/PAM split, Sudhanix schema). Original gaps: (1) the `sudhanixWelcomeDismissed` schema entry (BOOLEAN, OID `1.3.6.1.4.1.99999.1.1.1`) + `sudhanixUser` aux objectClass + the self-write ACL, all under `cn=sudhanix,cn=schema,cn=config`; (2) the `nsswitch.conf` Ubuntu 24.04 default-line trap that broke our `lineinfile` regex in `roles/ldap-client`; (3) the `libnss-ldap` (PADL, deprecated) vs `libnss-ldapd` + `nslcd` debate, and why we stayed on `libnss-ldap` (it works once nsswitch + nscd are right). Add the `nscd -i passwd` cache-flush note.
- [~] ~~**IT: Content Filtering**~~~~ — published 2026-05-06 with full prose pass (two-layer architecture, SSL-bumping ethics, timed_internet schedule as design choice). Original gaps: (the cause of the "no HTTPS egress" outage) or the `adult` host-group semantics in `host_vars/srv-gw`. Add: schedule rationale + nightly-down impact, how to clear a host from filter groups (`ips: []`), e2guardian → squid → upstream chain, where the bypass list lives.
- [ ] **[DRAFT — pending review]** **HTTPSFiltering** (1.8 KB) — Draft at `.claude/wiki-pages/HTTPSFiltering.txt` (rewritten as a short companion to ContentFilter rather than a full merge). Either expand with the e2guardian SSL MITM specifics + `timed_internet.sh` interaction, or merge into [[ContentFilter]] and redirect.
- [~] ~~**IT: Customized Ubuntu Packages**~~ — published 2026-05-06 with full prose pass (Internal repository architecture, packaging lifecycle, client-side GPG trust and pinning). Original gap: Draft at `.claude/wiki-pages/CustomizedUbuntuPackages.txt`. Says "xenial" only. Update for current state: focal + xenial + noble all live on apt.cttb, nightly cron at 1:00 AM via `runall.sh`, `--nocleanup` for shared pool. Point at `/srv/debmirror/scripts/dm-ubuntu-*.sh`.
- [ ] **[DRAFT — pending review]** **HostPackagesUsingReprepro** (4.7 KB, last touched 2022-03-04) — Draft at `.claude/wiki-pages/HostPackagesUsingReprepro.txt`. Mechanism still accurate. Add: focal added by Rui in 2022 outside ansible; noble added 2026-04-30 via updated `roles/debmirror/`; how to add a new release (defaults entry + new dm-ubuntu-XX.sh + runall.sh entry).
- [~] ~~**IT: HTTPS and SSL**~~~~ (4.3 KB / 2.2 KB) — Cross-check against [[AddTrustedCASystemWideOnUbuntu]]; document the CTTB Root CA path (`/usr/local/share/ca-certificates/CTTB-Root-CA.crt`, symlinked in `/etc/ssl/certs/`) deployed by `roles/common`. Note that no client config is needed once the role runs.
- [~] ~~**IT: Adding Trusted CAs**~~ — published 2026-05-06 with full prose pass (X.509 PKI lineage, OpenSSL-vs-NSS trust-store split, p11-kit shim explained, manual procedure preserved). Original ask: rename mentions to "Sudhanix / Ubuntu 24". Reference the ansible task that deploys the CA automatically; the manual procedure is now historical.
- [~] ~~**IT: NFS**~~ — published 2026-05-06 with full prose pass (Sun 1984 origin, NFSv2/3/4 evolution, AUTH_SYS trust model honesty, the 2026 export-ACL gotcha as worked debugging case). Original gap: `/etc/exports` on the `fileserver` LXD container (on srv-nas, Ubuntu 16.04) reached via `kit.chong@rui-desktop2 → administrator@fileserver`. Show how to add a subnet (current list: 10.11.30/16/10/9 .0/24), `exportfs -ra`, `showmount -e fileserver` to verify. Note that adding a new lab subnet *requires* an export update before autofs will work there.
- [~] ~~**IT: Autofs**~~ — published 2026-05-06 with full prose pass (Sun automounter origin, kernel/daemon split mechanics, touch-becomes-mount path explained). Original gap: Add: `roles/autofs` covers this automatically on Sudhanix; troubleshoot mounts via `findmnt /nfs/home/<user>`; reach-on-access (no eager mount); systemd vs init transition is invisible on 24.04.
- [~] ~~**IT: Unbound DNS Logging**~~ — published 2026-05-06 with full prose pass (NLnet Labs history, iterative recursion vs authoritative, unbound-control management). Original gap: Draft at `.claude/wiki-pages/UnboundLogConfiguration.txt`. Document the wiki-DNS-resolution incident (2026-05-04): `wiki.cttb` was resolving to a stale 10.11.1.31 because of a name conflict with the legacy LXC container. The fix touched `/etc/unbound/unbound.conf.d/cttb` on `ub-adult` and `ub-igdvs`, plus `unbound-control flush_zone cttb.`, plus a dnsmasq host-record on 10.11.1.19. Codify the "how to repoint a service hostname" workflow.
- [~] ~~**IT: Network Migration History**~~ — published 2026-05-06 with full prose pass (Netmask expansion, gateway evolution, operational lessons). Original gap: Audit for relevance; these are change-records from prior network rebuilds. Either fold into a single "Network Migrations" history page or archive.
- [~] ~~**IT: Infrastructure Overview**~~~~ (13.6 KB) — Add the `storehouse` container (10.11.1.43, Ubuntu 22.04, copyparty) and update the wiki entry to `wiki-2404` at 10.11.1.34. Note that 13 of the 15 srv-vm LXC containers are still on Ubuntu 16.04 (per the 2026-04-23 audit) — this is load-bearing context for the upgrade plan.
- [~] ~~**IT: Virtualization with LXD**~~ — published 2026-05-06 with full prose pass (System vs App containers, unprivileged mapping, ZFS snapshots/clones). Original gap: New article providing technical overview of system containers.
- [~] ~~**IT: Infrastructure Servers Configuration**~~ — published 2026-05-06 with full prose pass (Bare-metal setup, unprivileged container mounts, IPMI standards). Original gap: Either expand against the 2026-04-23 core-services audit (15-container srv-vm table, srv-nas, srv-gw, srv-git, etc.) or merge into [[System Overview]].
- [~] ~~**IT: Infrastructure Services**~~ — published 2026-05-06 with full prose pass (2026-04-23 core audit, physical host tier, 16.04 technical debt). Original gap: Replace with current service inventory (DNS/DHCP, LDAP, Asterisk, CUPS×3, Unbound×2, OpenVPN/jumpbox, MediaWiki, Ghost blogger, DRBU SIS, SLTP/Koha, Postfix/sendmail, storehouse). Cross-link each to its page.

**Storage / hosts**

- [~] ~~**IT: Backups**~~~~ — published 2026-05-06 with full prose pass (3-2-1 rule, Rsync's rolling-checksum algorithm, rrsync restricted keys). Original gap: Draft at `.claude/wiki-pages/Backups.txt`. Audit current `backupninja` + rsync+hardlinks setup: which hosts are backed up, schedule, retention, restore procedure, where snapshots live, how to verify. Without this page a junior IT person cannot recover from a host loss.
- [~] ~~**IT: Nagios**~~~~ — published 2026-05-06 with full prose pass (NetSaint→Nagios history, plugin architecture as load-bearing decision, check_by_ssh vs NRPE rationale, alert-flow filtering with worked case). Original gap: Document monitored hosts, checks, escalation path. Cross-reference the BACKLOG flag for the `mon` container (running but no monitoring daemon detected) and the `metrics` container (stopped on srv-nas).
- [~] ~~**IT: Printing**~~~~ — published 2026-05-06 with full prose pass (CUPS history Sweet 1997 → Apple 2007, IPP RFC 8010/8011 + PWG history, three-server divisional architecture, HP-vs-Xerox quirks with HPPS filter trap). Original gap:
- [~] ~~**IT: Printer Toner Logs**~~ — published 2026-05-06 with full prose pass (Admin topology, counter-chip gotcha, replacement history 2017-2023). Original gap: Verify against current toner inventory; possibly trim/archive entries older than two years.

**Identity / access**

- [~] ~~**Network Account User Guide**~~ — published 2026-05-06 with full prose pass (Roaming profiles, LDAP/NFS pillars, troubleshooting guides). Original gap: Draft at `.claude/wiki-pages/NetworkAccountUserGuide.txt`. Reframe for Sudhanix: home dir follows via NFS, password change via `passwd` on any LDAP-enabled machine, what happens at first login (Sudhanix welcome window, dismissable). Cross-link to the planned [[Migrating to Sudhanix 26]] page.
- [~] ~~**Change Password**~~ — published 2026-05-06 with full prose pass (LDAP/PAM handshake, security best practices, forgotten password procedures). Original gap: Draft at `.claude/wiki-pages/ChangePassword.txt`. Tiny. Add: the `sudhanix-cache-token` PAM hook caches the user's cleartext password to `/run/sudhanix-tokens/<uid>` for the welcome-window LDAP write — and is shredded by `sudhanix-shred-token` on session close. Users should know this exists.
- [~] ~~**IT: SSH**~~~~ — published 2026-05-06 with full prose pass (Ylönen 1995 → OpenSSH 1999 → SSH-2 RFCs 4251–4254, three-layer architecture, Tailscale jump-host pattern). The `Ssh` redirect remains. Original ask: the ProxyJump-key-auth intermittent issue (BACKLOG flag), and how IT keys are pushed via `roles/ldap-client` `%it` sudoers entry.
- [~] ~~**IT: Sudo**~~~~ — published 2026-05-06 with full prose pass (Coggeshall/Spencer 1980 SUNY Buffalo origin, sudoers grammar, %it LDAP stanza, polkit handoff explained, do/don't list with GTFOBins reference). Original ask:

**Desktop / software (mostly obsolete, prune aggressively)**

- [~] ~~**IT: Web Browsers**~~ — published 2026-05-06 with full prose pass (browser-market history Mosaic→Netscape→Chrome, Chrome NFS SingletonLock as worked case, Firefox apt-vs-snap rationale, Zen via Flatpak). Original gap:
- [~] ~~**IT: Legacy Lubuntu Customization**~~ — published 2026-05-06 with full prose pass (Openbox/LXDE legacy stack, ICCCM/EWMH compliance, transition rationale). Original gap: Draft at `.claude/wiki-pages/LubuntuCustomization.txt` (legacy-marker rewrite). Obsolete (Lubuntu/openbox/lxpanel). Mark deprecated and redirect to [[IT:Sudhanix]]; keep in a "Legacy" category for historical reference.
- [~] ~~**IT: Legacy Desktop Environments**~~ — published 2026-05-06 with full prose pass (Cinnamon/MATE/Unity rejection rationale, memory footprint comparison). Original gap: Stubs from old desktop alternatives. Either delete or mark deprecated; Sudhanix is XFCE-only.
- [~] ~~**IT: Automatic System Updates**~~ — published 2026-05-06 with full prose pass (unattended-upgrades configuration, systemd timers for APT periodic tasks, lab distraction policy). Original gap: Draft at `.claude/wiki-pages/AutomaticSystemUpdates.txt`. Document Sudhanix policy explicitly (whether unattended-upgrades is enabled by intent or not; what's pinned). Currently a stub.

**Git / dev**

- [~] ~~**IT: Gitolite 3 and Gitweb**~~ — published 2026-05-06 with full prose pass (SSH forced-command architecture, access management runbook, @INC fix). Original gap: Tiny. Document the current `git.cttb` host (gitolite), the broken `update` hook (Perl `@INC` missing gitolite lib — BACKLOG flag), the `ansible-new` repo path (`git@srv-git.cttb:ansible-new`), and how to add a user/repo.

**Possibly obsolete — audit, then archive or rewrite**

- [~] ~~**IT: Legacy Wireless Access Points**~~ — published 2026-05-06 with full prose pass (Tomato era history, bridge-only mode cabling rule). Original gap: Do we still run Asus Tomato firmware on any AP? If not, mark legacy.
- [~] ~~**IT: Mobile Devices**~~ — published 2026-05-06 with full prose pass (MacBook OpenDirectory, Wi-Fi tiers, monastic compatible usage). Original gap: Vague. Either describe supported device types (MacBooks via NFS, tablets, phones) or merge.
- [ ] **HelpfulWebSitesForContentFiltering** (598 B) — Last meaningful edit referenced "Sent from Rui to Spike, April 2018." Audit and either refresh or merge into [[ContentFilter]].
- [~] ~~**IT: Content Filtering FAQ**~~ — published 2026-05-06 with full prose pass (User troubleshooting for YouTube/TLS, evaluator resources). Original gap: Stub. Merge into [[ContentFilter]].
- [~] ~~**User Help and Support**~~ — published 2026-05-06 with full prose pass (Support tiers, self-help philosophy, common symptom translations). Original gap: Audit and refresh for Sudhanix; otherwise mark stale.

**Delete**

- [ ] **Test** (2.8 KB, 2017-02-03) and **Test1** (712 B, 2026-05-03) — sandbox pages, no production value.

### Pages That Should Exist But Don't

These show up repeatedly in `UPDATE_JOURNAL.md` but have no wiki page yet, and are not (or only partially) covered by the planned IT:Sudhanix-* pages above.

- [~] ~~**IT:Storehouse**~~ — published 2026-05-06 with full prose pass (h5ai-over-nginx architecture, curated vs upstream asset philosophy, manual rsync+tar workflow). Original gap: Draft at `.claude/wiki-pages/IT_Storehouse.txt`. copyparty file server (storehouse.cttb / 10.11.1.43, Ubuntu 22.04 LXC on srv-vm). What it is, what lives there (`/srv/storehouse/ansible/`), how to upload (rsync+tar for symlinks; scp for single files; chown to `storehouse:storehouse`), how clients consume it (`ansible_assets_url`). Companion to the Asset Manifest page.
- [~] ~~**IT:DNS Architecture**~~ — published 2026-05-06 with full prose pass (Mockapetris 1983, RFC 1034/1035, three-layer split with each layer's failure mode, the 2026 wiki repointing as worked case). Original ask: How to add or repoint a service hostname end-to-end (dnsmasq host-record → `unbound-control flush_zone cttb.` → verify across resolvers). The 2026-05-04 wiki-DNS-conflict incident is the canonical cautionary tale.
- [x] ~~**IT:Sudhanix Welcome Window**~~ — Either its own page or a substantial subsection of [[IT:Sudhanix]]. Cover: the `sudhanixWelcomeDismissed` LDAP attribute and ACL, the `sudhanixUser` aux objectClass, the per-uid token-file handoff via `pam_exec` (`sudhanix-cache-token` / `sudhanix-shred-token`), the GTK3 client at `/usr/local/bin/sudhanix-welcome`, fail-soft semantics. Novel CTTB infra worth its own treatment.
- [ ] **IT:Sudhanix First-Login Bootstrap** — Either its own page or a major subsection of [[IT:Sudhanix]]. Cover: the user journey on first Sudhanix-26 login (X-session pipeline → migration → first-time setup → welcome window) and *why* a per-user bootstrap is needed despite system-wide `/etc/xdg` defaults. The `pam_mkhomedir` gap on legacy LDAP clients (existing NFS homes pre-date the PAM addition, so mkhomedir is a no-op for them). What the script quarantines (`~/.config/{xfce4,lxqt,openbox,plank}`, `~/.gtkrc-2.0`, `~/.config/gtk-3.0/settings.ini` → `~/.config/.pre-sudhanix-26.<ts>/`) and why each one would otherwise shadow the system defaults. What it preserves across the upgrade (`~/.config/gtk-3.0/bookmarks`). The marker-file idempotency (`~/.config/sudhanix/v26-bootstrapped`). Where the trigger lives (`/etc/X11/Xsession.d/55sudhanix-firstlogin`) and the XDG-autostart fallback. Sysadmin-callable form (`sudhanix-migrate-home [--dry-run] <user>...`) for pre-migrating existing student/staff homes from the fileserver before a rollout. The per-user log/notes (`~/.cache/sudhanix-firstlogin.log`, `~/.sudhanix-migration-NOTES.txt`). Cross-link from [[Migrating to Sudhanix 26]] (user-facing) which already references the first-login experience implicitly.
- [~] ~~**IT:Apt Mirror Operations**~~ — published 2026-05-06 with full prose pass (Ubuntu archive pool/dists structure, Debmirror synchronization phases, GPG EXPKEYSIG worked case). Original gap: Draft at `.claude/wiki-pages/IT_Apt_Mirror_Operations.txt`. apt.cttb / debmirror runbook: where the scripts live (`/srv/debmirror/scripts/dm-ubuntu-*.sh` + `runall.sh`), how nightly cron is wired, how to add a release, how to verify a sync (the 2026-04-30 noble add is the worked example), the GPG-key-expiry trap from Chrome's mirror.

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
- [x] ~~GRUB menu strings~~ — `GRUB_DISTRIBUTOR` auto-resolves via `/etc/os-release` (NAME=Sudhanix). Menu now shows 'Sudhanix GNU/Linux'. Also added `GRUB_TIMEOUT_STYLE=menu` + `GRUB_TIMEOUT=3` so menu is actually visible at boot. Verified live (2026-05-05)
- [ ] **GRUB theme** — currently default Ubuntu purple. Build/deploy a Sudhanix-branded theme (logo + colors) at `/boot/grub/themes/sudhanix/` and reference in `/etc/default/grub`
- [x] ~~Plymouth boot splash~~ — Sudhanix theme deployed: lotus PNG (FLUX render), macOS-style script with progress bar, registered via `update-alternatives`, baked into initrd. Required adding `quiet splash` to `GRUB_CMDLINE_LINUX_DEFAULT`. Cleanup task strips macOS `._*` forks. Verified visible at boot (2026-05-05)
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
- [x] ~~Playbook rename~~ — `cs-lab-2404.yml` → `install-sudhanix-cslabs.yml` (drops Ubuntu version, adds Sudhanix brand + "install" verb to clarify intent: CS-lab post-install configuration). Done 2026-05-05
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
d in `/etc/ssl/certs/` (2026-05-04)
