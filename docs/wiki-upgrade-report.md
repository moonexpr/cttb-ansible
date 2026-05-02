# MediaWiki Upgrade Report: wiki.cttb

**Date:** 2026-05-02
**Author:** JC / Claude Code
**Status:** Assessment — no changes made

---

## 1. Current State

The CTTB internal wiki (`wiki.cttb`, 10.11.1.31) runs as an LXC container named `wiki` on `srv-vm`.

| Component   | Installed        | End-of-Life     | Years Past EOL |
|-------------|------------------|-----------------|----------------|
| Ubuntu      | 16.04.7 LTS      | April 2021      | 5              |
| MediaWiki   | 1.29.1           | ~September 2018 | 8              |
| PHP         | 7.0.33           | December 2018   | 8              |
| MySQL       | 5.7.33           | October 2023    | 3              |

- **Install path:** `/var/www/html/w/` (MediaWiki 1.29.1 source tree)
- **Old unused install:** `/var/lib/mediawiki-1.29.1/` (separate LocalSettings, not serving traffic)
- **Config backup:** `/home/administrator/mediawiki-conf-backup/LocalSettings.php`
- **DB table prefix:** `mediawiki` (tables are `mediawikipage`, `mediawikirevision`, etc.)
- **Disk:** 12 GB used of 1.7 TB (`data/lxd/containers/wiki`)
- **Other content:** `/var/www/html/` also serves `CTTB-tech-use-guide.pdf`, `files/`, `images/`

### Why this matters

Every component is years past its end-of-life date. No security patches have been issued for any of these versions in years. The wiki is on an internal network, which limits exposure, but any compromised internal machine could pivot to it. MediaWiki 1.29 has known vulnerabilities including XSS and remote code execution (CVE-2021-44858, CVE-2021-45038, among others that affect all unpatched pre-1.35 installs).

---

## 2. Proposed Approach: Fresh Container Migration

Rather than upgrading the OS and software in-place (which chains four Ubuntu release upgrades together and risks breakage at each step), the recommended approach is:

1. Build a new LXC container with a modern base
2. Migrate the wiki database and files into it
3. Step MediaWiki through its required upgrade path inside the new container
4. Verify on `wikitest.cttb`, then swap DNS to `wiki.cttb`

The old container remains untouched throughout, serving as an instant rollback.

### Why not upgrade in-place?

- Ubuntu 16.04 -> 24.04 requires four sequential `do-release-upgrade` passes (16.04 -> 18.04 -> 20.04 -> 22.04 -> 24.04). Each one can fail and leave the system in a broken state.
- PHP jumps from 7.0 -> 7.2 -> 7.4 -> 8.1 -> 8.3 across those upgrades. MediaWiki's compatibility with each PHP version must be matched at each step.
- MySQL 5.7 -> 8.0 migration has known gotchas with character sets and authentication changes.
- If anything goes wrong mid-upgrade, the wiki is down with no clean rollback.

A fresh container avoids all of this. The database is the only stateful artifact that needs careful migration.

---

## 3. Migration Steps (Detailed)

### Step 1: Freeze and back up the current wiki

- Put the current wiki into read-only mode (`$wgReadOnly` in LocalSettings.php)
- Dump the database: `mysqldump -umediawiki -p'<DB_PASSWORD>' --default-character-set=utf8 mediawiki > wiki-dump.sql`
- Copy the images directory: `/var/www/html/w/images/`
- Copy `LocalSettings.php` for reference (DB name, secret keys, extensions, site config)
- Copy any static content from `/var/www/html/` (the PDF, `files/`, etc.)

### Step 2: Create new LXC container

On `srv-vm`:

```
lxc launch ubuntu:24.04 wiki-2404
```

Install base packages:

```
apt install apache2 php8.3 php8.3-mysql php8.3-xml php8.3-mbstring \
    php8.3-intl php8.3-gd php8.3-curl mariadb-server imagemagick git
```

Ubuntu 24.04 ships PHP 8.3 and MariaDB 10.11 — both well-supported by MediaWiki 1.43.

### Step 3: MediaWiki stepping upgrade

MediaWiki requires upgrading through Long-Term Support (LTS) releases. You cannot skip LTS versions because each one includes database schema migrations that build on the previous one.

The path:

| Step | MediaWiki | Minimum PHP | Notes |
|------|-----------|-------------|-------|
| Import | 1.35.14 (LTS) | 7.3 | First step — can read a 1.29 database |
| Upgrade | 1.39.11 (LTS) | 7.4 | Intermediate step |
| Upgrade | 1.43.x (LTS) | 8.1 | Target version, runs on PHP 8.3 |

Note: MW 1.31 step is skipped. Per MediaWiki docs, upgrades from 1.29 can go directly to 1.35 (supports upgrades from up to two LTS releases back).

For each step:

1. Download the MediaWiki tarball from `releases.wikimedia.org`
2. Extract to `/var/www/html/w/`
3. Copy `LocalSettings.php`, preserving `$wgDBprefix = "mediawiki";`
4. Run `php maintenance/update.php` — this migrates the database schema
5. Verify the wiki loads in a browser
6. Proceed to next version

The database is small (17.3 MB in wiki tables), so each `update.php` run will be fast.

### Step 4: Extensions and customization

Active extensions to reinstall (all bundled with MW core):

- **ImageMap** — bundled through 1.43
- **Interwiki** — bundled through 1.43
- **WikiEditor** — bundled through 1.43

Review `LocalSettings.php` from the old install for:

- **Skins** — MW 1.35+ changed the default skin from Vector legacy to Vector 2022. The old skin is still available.
- **Custom settings** — `$wgLogo`, `$wgServer`, file upload settings, user permissions, etc. These generally carry forward but should be reviewed.

### Step 5: Restore static content

Copy the non-wiki files (`CTTB-tech-use-guide.pdf`, `files/`, etc.) to the new container's web root.

### Step 6: Verify on wikitest.cttb

- Set DNS for `wikitest.cttb` to the new container's IP
- Browse the wiki, check page rendering
- Verify image thumbnails generate correctly (requires ImageMagick/GD)
- Test search
- Check user accounts can log in
- Spot-check CJK content for encoding issues
- Verify the IT:Ansible page and other active content

### Step 7: DNS cutover

Once verified, point `wiki.cttb` to the new container's IP (or reassign IPs).
Keep the old `wiki` container stopped but intact for at least a month as rollback insurance.

---

## 4. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `update.php` fails at a stepping version | Medium | Blocks upgrade | Restore from dump, research the specific error. MW upgrade errors are well-documented. |
| Extensions incompatible with MW 1.43 | Low | Missing functionality | All 3 active extensions are bundled with core. |
| Character encoding issues in DB migration | Low-Medium | Garbled text (especially CJK content) | Use `--default-character-set=utf8` on dump. Verify a sample of CJK pages after each step. |
| Old container IP reassignment breaks something | Low | Brief downtime | Do DNS cutover during off-hours. |
| Users have passwords that don't work with new auth | Low | Login failures | MW password hashes are forward-compatible. Test a few accounts. |

### CJK text note

Given CTTB's multilingual content (English, Chinese), character encoding deserves extra attention. MySQL 5.7's `utf8` is actually `utf8mb3` (3-byte, no full Unicode). MariaDB 10.11 defaults to `utf8mb4`. The dump/restore should be tested with a handful of Chinese-heavy pages to confirm no data corruption.

---

## 5. Estimated Effort

- **Backup and new container setup:** ~30 minutes
- **Three-step MediaWiki upgrade:** ~1-2 hours (mostly waiting on `update.php` and verifying)
- **Extension and config review:** ~30 minutes
- **Verification on wikitest.cttb:** ~30 minutes
- **DNS cutover:** ~5 minutes

Total: roughly 3-4 hours of focused work.

---

## 6. Alternatives Considered

### In-place OS + MW upgrade
Four chained `do-release-upgrade` runs with MW upgrades interleaved. Higher risk, no clean rollback, same amount of MW stepping work. Not recommended.

### Replace with a different wiki
A simpler tool (BookStack, Wiki.js, DokuWiki) could replace MediaWiki entirely. This avoids the ongoing maintenance burden but requires content migration of a different kind. Not recommended — the wiki is actively used and MediaWiki is familiar to the team.

### Do nothing
The wiki works today on the internal network. However, every component is years past EOL with known CVEs. The longer this waits, the harder the eventual migration becomes. Not recommended.

---

## 7. Gathered Data

| Item | Value |
|------|-------|
| **Database size** | 66 MB total (`/var/lib/mysql/`), 17.3 MB in prefixed tables |
| **Database name** | `mediawiki` (table prefix: `mediawiki`) |
| **Total pages** | 125 |
| **Total revisions** | 1,456 |
| **Last edit** | 2026-05-01 (John.chandara and Jerry.hsu editing IT:Ansible) |
| **Images volume** | 12 MB |
| **Active extensions** | ImageMap, Interwiki, WikiEditor |
| **Commented-out extensions** | InputBox, PdfHandler, SyntaxHighlight_GeSHi, MarkdownExtraGeshiSyntax |
| **Other services** | Apache, MySQL, PHP 7.0-FPM, SSH, cron, unattended-upgrades — wiki stack only |
| **Static content** | `CTTB-tech-use-guide.pdf`, `files/`, `images/` also served from `/var/www/html/` |

**Note:** The database also contains a set of unprefixed tables (3 pages, 8 revisions from 2015) from an earlier install at `/var/lib/mediawiki-1.29.1/`. These are not used by the live wiki. The live wiki uses `mediawiki`-prefixed tables served from `/var/www/html/w/`.

---

## 8. Recommendation

This wiki is **actively used** (125 pages, 1,456 revisions, edited daily) and runs on a stack that is entirely end-of-life. The upgrade is justified and should be scheduled.

### Plan

1. Launch `wiki-2404` container (Ubuntu 24.04 LTS) on `srv-vm`
2. Set up as `wikitest.cttb` for verification
3. Migrate data and step through MW 1.35 -> 1.39 -> 1.43
4. Verify thoroughly on `wikitest.cttb`
5. Swap DNS to `wiki.cttb` when confirmed working
6. Keep old `wiki` container stopped as rollback for 30 days

### Target stack

| Component | Version |
|-----------|---------|
| Ubuntu | 24.04 LTS |
| MediaWiki | 1.43.x LTS |
| PHP | 8.3 |
| MariaDB | 10.11 |
