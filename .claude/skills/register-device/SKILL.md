---
name: register-device
user-invocable: true
argument-hint: "<MAC> [category]"
description: >
  Move one device on lxc-dnsmasq from the block13 quarantine pool into a
  working DHCP pool by appending a structured dhcp-host entry to
  /etc/dnsmasq-hosts/<category> on the box and mirroring the same line into
  the local config clone. Block13 clients have DNS=10.11.13.13 (dead) and
  default route=0.0.0.0 by design — they have no DNS and no internet until
  registered. TRIGGER on "register a device", "get this device online",
  "move <MAC> out of quarantine", "unblock <MAC>", "register <MAC> in
  <category>", `/register-device <MAC> [category]`, or when /sysadmin
  routes here. One device per invocation — never bulk.
---

Move one device out of block13 quarantine by appending a single line to
`/etc/dnsmasq-hosts/<category>` on `lxc-dnsmasq`, mirroring the same line
into the local config clone, and SIGHUPing dnsmasq.

## Scope

- **One device per run.** A bulk-register-from-AP workflow is intentionally
  out of scope — dnsmasq has no AP / SSID / switchport data, so "all
  devices on the Earth Store Hall AP" cannot be answered from this box.
  If the user asks for bulk, route them to get a MAC list from the AP
  controller (UniFi etc.) and run this skill per MAC.
- Replaces Rui's interactive `register.py` for Claude-driven sessions.
  Uses Rui's `next-ip.py` for IP allocation so the address pools stay
  consistent with the existing workflow.
- Hosts-DB content is **out of band of Ansible** (cttb-ansible#89): this
  skill writes directly to the live box and the git clone, not via a play.

## Procedure

1. **Gather inputs.** The slash-command argument supplies the MAC (and
   optionally the category). Ask the user, in one `AskUserQuestion` batch,
   for anything still missing: **category** (default `adult` for long-term,
   `visitors` for temp 10.11.200.x; the full set is `adult | visitors | drbu
   | servers | switches | voip | waps | restricted | testlab | temp`),
   **owner** (full name), **device type** (`phone | laptop | desktop |
   tablet | other`), **device model** (free-text), **hostname** (suggest
   `<first-name-lowercase>-<type>`, e.g. `jc-iphone`, `jc-macbook`), and
   **comment** (free-text, defaults to empty). Use defaults for the rest:
   `expires=2046-12-31` for long-term categories or `today+90d` for
   `visitors`/`temp`; `registrar=$(whoami)` on the workstation
   (`<redacted>` on your Mac).

2. **Paste-buffer / duplicate guard.** Before any write, the helper script
   greps every `/etc/dnsmasq-hosts/*` on the box for the candidate MAC and
   refuses if it is already registered, printing the existing line.
   Surface that line to the user so they can spot a paste-buffer
   carryover (see the iPhone/iMoonexpr session of 2026-05-19 14:58 where
   the same MAC arrived twice). Also refuse on hostname collision against
   the third field of any existing entry.

3. **Allocate the IP.** The helper invokes `next-ip.py` on the box:
   `resident` for category `adult`, `visitor` for `visitors`. For any
   other category, the caller MUST pass `--ip <IP>` explicitly (next-ip.py
   does not cover those pools). Show the IP the user is about to commit
   to before writing.

4. **Compose + write.** The helper composes the exact modern-format line:
   `<mac-lowercase>,<ip>,<hostname>\t# Registered on: <ctime>. Owner: <owner>, type: <type>, model: <model>, expiration date: <yyyy-mm-dd>, registrar: <registrar>, comment: <comment>.`
   It appends to `/etc/dnsmasq-hosts/<category>` on the box, then mirrors
   the same line into `~/Garden/external/dnsmasq/dnsmasq-hosts/<category>`
   in the local clone. **No auto-commit** — the user reviews and commits
   the local clone later.

5. **Reload + verify.** The helper sends `SIGHUP` to dnsmasq (no restart;
   `dhcp-hostsdir` re-reads on HUP and on file change, but HUP is
   belt-and-suspenders), then confirms `systemctl is-active dnsmasq`,
   greps the new entry, and checks the journal for the
   `read /etc/dnsmasq-hosts/<category>` line.

6. **Hand back.** Tell the user to **toggle Wi-Fi off and on** on the
   device so it releases the block13 lease and DHCPs onto the new
   address (default route `10.11.1.1`, DNS `10.11.1.29` via option 6).
   The new lease appears in `/var/lib/misc/dnsmasq.leases` within
   seconds of the Wi-Fi toggle.

The orchestration is yours; the writes go through the helper script so
the procedure is reproducible and not regenerated each run.

## Edge cases

- **Lowercase MAC.** Existing hosts files use lowercase MACs — the
  helper normalizes before any compare or write. A mixed-case MAC from
  the user is fine; a mixed-case stored entry would defeat the
  duplicate check, so the comparator is also case-insensitive.
- **Same MAC pasted twice.** Refuse and show the existing entry; do
  not silently overwrite (dnsmasq treats duplicate dhcp-host entries as
  last-wins, which would corrupt the prior binding).
- **Hostname collision.** Refuse and ask the user to pick a new
  hostname (e.g. append `-2`). Never auto-suffix without confirmation.
- **Local clone missing.** If `~/Garden/external/dnsmasq/dnsmasq-hosts/<category>`
  doesn't exist, the box write still goes through; the helper warns and
  skips the mirror. Drift grows by one line — surface to the user.
- **Box unreachable.** If `cttb-ct.sh exec dnsmasq` fails, abort before
  touching the local clone. Never end with a local entry that isn't on
  the box.

## Privacy

This skill lives under `.claude/skills/` (gitignored). Do not paste its
contents, the helper script body, or the `.claude/sysadmin/*` script
paths into wiki pages, PRs, or any public artifact. Internal use only.

## Resources

| Path | Loaded / run when |
|---|---|
| `scripts/register-device.sh` | Run for every invocation: performs the duplicate/hostname/IP/format/write/SIGHUP/verify sequence in one envelope. Treat as the executable body of step 2–5. |

External, referenced (not vendored by this skill):

| External path | Role |
|---|---|
| `.claude/sysadmin/cttb-ct.sh exec dnsmasq …` | Container shell into lxc-dnsmasq; the only way the helper reaches the box. |
| `/home/administrator/dnsmasq.git/next-ip.py` (on box) | Returns next free IP. `resident` → adult pool; `visitor` → 10.11.200.x. |
| `/etc/dnsmasq-hosts/<category>` (on box) | The dhcp-hostsdir file appended to. |
| `~/Garden/external/dnsmasq/dnsmasq-hosts/<category>` (local) | Mirror destination; the live config git repo. Override path via `DNSMASQ_CLONE` env var. |
| `/etc/dnsmasq.conf` line 106 / line 120 (on box) | Why block13 is broken: option-6 → `10.11.13.13` (dead), option:router → `0.0.0.0` (no route). |
| cttb-ansible#89 | Tracks Ansible coverage gap + git/deployed drift for the hosts DB. |
