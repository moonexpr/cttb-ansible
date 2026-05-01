# Task: Fix expired Chrome GPG key on apt.cttb mirror

## Problem

The Chrome repo mirror at `http://apt.cttb/mirrors/chrome` has an expired GPG signing key (`EXPKEYSIG 4EB27DB2A3B88B8B`). The `InRelease` file itself is signed with the expired key — updating the local keyring on clients doesn't help because apt validates the mirror's own signature.

This blocks `apt-get update` for any machine with the Chrome repo configured.

## Infrastructure

- **apt.cttb** resolves to the `debmirror` container (10.11.1.22) on srv-nas (10.11.1.5)
- Chrome mirror lives at: `/srv/debmirror/mirror/chrome/` (verify exact path)
- The mirror was likely created with a manual rsync or debmirror of `http://dl.google.com/linux/chrome/deb/`

## Access

- SSH: `ssh administrator@srv-nas.cttb` (ed25519 key deployed), then `sudo lxc exec debmirror -- bash`
- Sudo password on srv-nas: `4m1t0f0`
- Via jumphost: `ssh -o ProxyJump=johnchandara@rui-desktop2.taile43dc0.ts.net administrator@srv-nas.cttb`

## Goal

1. SSH into the debmirror container
2. Find the Chrome mirror directory (likely under `/srv/debmirror/mirror/chrome/` or `/var/www/html/mirrors/chrome/`)
3. Re-sync the Chrome repo from Google:
   ```bash
   # Find the mirror path
   find /srv/debmirror /var/www/html -name "chrome" -type d 2>/dev/null
   
   # Re-sync (example — adjust path)
   cd /path/to/chrome/mirror
   wget -N https://dl.google.com/linux/chrome/deb/dists/stable/InRelease
   wget -N https://dl.google.com/linux/chrome/deb/dists/stable/Release
   wget -N https://dl.google.com/linux/chrome/deb/dists/stable/Release.gpg
   wget -N https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages.gz
   ```
   Or if there's a sync script already, find and re-run it.
4. Also update the signing key served at `http://apt.cttb/Google-linux_signing_key.pub`:
   ```bash
   curl -o /var/www/html/Google-linux_signing_key.pub https://dl.google.com/linux/linux_signing_key.pub
   ```

## Important

- The debmirror container is Ubuntu 16.04 — `wget` or `curl` should work for HTTPS if ca-certificates is installed. If not, try `curl -k` or install ca-certificates first.
- The container may not have direct WAN/HTTPS access. If so, download files on a machine that does (e.g., srv-gw via squid proxy, or your local machine) and scp them in.
- Don't disrupt the noble debmirror sync that may still be running (`ps aux | grep debmirror`).

## Verification

```bash
# From dvgs-lab3 or any lab machine
curl -sI http://apt.cttb/mirrors/chrome/dists/stable/InRelease | head -5
# Should return HTTP 200

# Test apt update with Chrome repo
apt-get update -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=/dev/null \
  -o "Acquire::AllowInsecureRepositories=false" \
  -o "Dir::Etc::trusted=/usr/share/keyrings/google-chrome.asc" 2>&1
```

## Document

Add a section to `UPDATE_JOURNAL.md` documenting what was changed and mark the Chrome GPG key backlog item as done.
