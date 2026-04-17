# Sprint Plan

**Goal:** Eliminate version-forked roles by unifying common and desktop role families into single roles with OS-version dispatch, lay the foundation for directory-driven desktop customization, and clean up inventory clutter.
**Date:** 2026-04-16

---

## Phase 1 — Unify the Common Role Family

**Purpose:** Merge `common`, `common-20.04`, and `common-22.04` into a single `common` role that handles all Ubuntu versions via variable and task dispatch. This comes first because `desktop` depends on `common` via meta/main.yml — the foundation must be solid before unifying the consumer.

**Constraints and assumptions:**
- No live hosts available — validation is static only (syntax-check, list-tasks, diff audit)
- The dispatch pattern follows Red Hat GPA: `include_vars` with `vars/Ubuntu_{major}.yml` for platform-specific values, `first_found` with `tasks/setup/Ubuntu_{major}.yml` for platform-specific tasks
- `main.yml` becomes an orchestrator only — no inline tasks
- All variables remain functionally identical — this phase does not rename or namespace variables (that's future work)
- `common-22.04` was forked from `common-20.04` with Ansible 2.20 modernization fixes — those fixes should be the 22.04/24.04 path, not backported to 20.04
- Old roles move to `.deprecated/` after unification, not deleted
- ARCHITECT may decide how to split shared vs version-specific tasks based on the diff classification
- If a task exists in one version but not another, ARCHITECT decides whether it's version-specific or a gap — does not need to escalate unless the intent is ambiguous

### Standing Permissions — Phase 1
- Specialists may create/edit files under `roles/common/`, `roles/.deprecated/`, `plays/`, and role `meta/main.yml` files only
- On ambiguous scope: conservative interpretation, note assumption, continue
- On interface ambiguity: specialist messages ARCHITECT; ARCHITECT resolves or escalates
- DIRECTOR may: choose implementation approach, skip tasks with recorded rationale, apply temporary workarounds within phase scope
- DIRECTOR may NOT: change phase definitions, add external dependencies not in SPRINT_PLAN.md, alter anything approved in Spec without flagging it in DIRECTOR_REPORT.md

**Definition of done:**
- Single `common` role exists with `vars/Ubuntu_20.yml`, `vars/Ubuntu_22.yml` (and `Ubuntu_24.yml` if 24.04 differences are identified)
- `tasks/main.yml` uses include_vars loop + first_found dispatch — no inline tasks
- `tasks/setup/default.yml` contains shared tasks; `tasks/setup/Ubuntu_{major}.yml` contains version-specific tasks
- Every task from all three old roles is accounted for in the unified role (diff audit confirms nothing dropped)
- `ansible-playbook plays/base.yml --syntax-check` passes
- `ansible-playbook plays/cs-lab-2404.yml --syntax-check` passes
- `ansible-playbook plays/cs-lab-2404.yml --list-tasks` shows correct task resolution
- Old roles moved to `roles/.deprecated/common-20.04/` and `roles/.deprecated/common-22.04/`
- `meta/main.yml` dependencies in `desktop-22.04` and `server` updated to point to unified `common`

### Tasks — Phase 1

#### Task 1.1: Build unified role structure and orchestrator main.yml
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending

Create the unified `roles/common/` role structure with Red Hat GPA dispatch pattern.

**Deliverables:**
- `roles/common/tasks/main.yml` — orchestrator only (include_vars + first_found dispatch, no inline tasks). Remove old backup files (main.yml.1, main.yml.2.*, etc.)
- `roles/common/tasks/setup/default.yml` — shared tasks that are identical across all versions:
  - custom apt sources.list (use the 20.04/22.04 template with `[arch=amd64]`)
  - add additional apt repo
  - refresh the mirrors
  - install apt-add-repository (software-properties-common)
  - Set up authorized_key (use 22.04 modern syntax: `lookup('file', ...)`)
  - set explicit proxy
  - sync time (include_role: time-server)
  - install CTTB CA cert (include_role: cttb-ca-client)
  - fix /etc/hosts
  - make ssh use ipv4 only (use `insertbefore` from 20.04/22.04, not `insertafter` from old)
  - enable centralized logging
  - enable Wake On LAN (from 20.04/22.04, not in old role)
  - upgrade ansible to latest
  - remove some software (shared list: popularity-contest, nano, avahi-daemon)
  - remove sw requested for this box
  - install basic software (shared list — the intersection of all three)
  - install sw requested for this box
  - disable ipv6
  - account default .bashrc (from 20.04/22.04)
  - vim saner defaults
  - customize settings for administrator (use 20.04/22.04 pattern: copy bashrc+vimrc from skel)
  - apt autoremove
  - dist-upgrade + autoremove purge
  - set the system locale (use `changed_when: false` from 22.04)
- `roles/common/tasks/setup/Ubuntu_20.yml` — 20.04-specific tasks:
  - add cttb custom ubuntu repo key (via apt_key — deprecated but needed for 20.04)
  - add ansible repo key (via apt_key)
  - add ansible repo mirror (without signed-by)
  - install basic software extras for 20.04: packages using `state: latest`, `install_recommends: no`
  - Version-specific package differences defined via vars
- `roles/common/tasks/setup/Ubuntu_22.yml` — 22.04/24.04-specific tasks:
  - download cttb repo key (get_url to /usr/share/keyrings/)
  - download ansible repo key (get_url to /usr/share/keyrings/)
  - add ansible repo mirror (with signed-by=/usr/share/keyrings/ansible.asc)
  - install basic software using `state: present`, `install_recommends: no`
  - Version-specific package differences defined via vars
- `roles/common/vars/Ubuntu_20.yml` — 20.04-specific variables:
  - `common_remove_sw` list (may include extra packages from old role: snapd, snap-confine, etc.)
  - `common_install_sw` list with 20.04-specific packages
  - Any APT key/repo URLs specific to 20.04
- `roles/common/vars/Ubuntu_22.yml` — 22.04-specific variables:
  - `common_remove_sw` list
  - `common_install_sw` list with 22.04-specific packages (mlocate, net-tools, binutils)
  - Any APT key/repo URLs specific to 22.04
- `roles/common/defaults/main.yml` — unchanged (disable_ipv6: True, centralized_logging: false)
- `roles/common/handlers/main.yml` — unchanged (restart rsyslog, reload ssh)
- `roles/common/templates/sources.list.j2` — use 20.04/22.04 version with `[arch=amd64]`
- `roles/common/files/` — merge all conf files from all three roles:
  - Keep existing: 10-centralized-logging.conf, disable-ipv6.conf, vimrc, ssh_keys/ansible.pub, cttb-repo.gpg.key
  - Add from 20.04/22.04: bashrc, ethernet-wake-on-lan.conf
  - Keep unattended-upgrades (may be referenced by old hosts)
  - Do NOT copy globalkeyshortcuts.conf or LXTerminal.desktop (desktop-layer files, not common)
- Remove old cruft from tasks/: environment, main.yml.1, main.yml.2.*, main.yml.3.*, main.yml.4.*, main.yml.5.*

**Acceptance criteria:**
1. `roles/common/tasks/main.yml` contains ONLY include_vars + first_found dispatch, no inline tasks
2. `roles/common/tasks/setup/default.yml` contains all shared tasks
3. `roles/common/tasks/setup/Ubuntu_20.yml` contains 20.04-specific tasks
4. `roles/common/tasks/setup/Ubuntu_22.yml` contains 22.04-specific tasks
5. `roles/common/vars/Ubuntu_20.yml` and `roles/common/vars/Ubuntu_22.yml` exist with version-specific variables
6. All files/ assets from all three roles are present in unified role
7. No old backup files remain in tasks/
8. Every task from the three original roles is accounted for (nothing dropped)

**Planning note:** Specialist should confirm understanding of the diff classification before implementing.

---

#### Task 1.2: Deprecate old roles and update meta dependencies
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending (depends on 1.1)

**Deliverables:**
- Move `roles/common-20.04/` to `roles/.deprecated/common-20.04/`
- Move `roles/common-22.04/` to `roles/.deprecated/common-22.04/`
- Update `roles/desktop-22.04/meta/main.yml`: change dependency from `common-22.04` to `common`
- Verify `roles/desktop/meta/main.yml` already depends on `common` (no change needed)
- Verify `roles/server/meta/main.yml` already depends on `common` (no change needed)

**Acceptance criteria:**
1. `roles/.deprecated/common-20.04/` exists with all original files
2. `roles/.deprecated/common-22.04/` exists with all original files
3. `roles/common-20.04/` and `roles/common-22.04/` no longer exist
4. `roles/desktop-22.04/meta/main.yml` depends on `common`
5. `roles/desktop/meta/main.yml` depends on `common`
6. `roles/server/meta/main.yml` depends on `common`

---

#### Task 1.3: Validation and diff audit
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending (depends on 1.2)

**Deliverables:**
- `ansible-playbook plays/base.yml --syntax-check` passes
- `ansible-playbook plays/cs-lab-2404.yml --syntax-check` passes
- `ansible-playbook plays/cs-lab-2404.yml --list-tasks` shows correct task resolution
- Diff audit: produce a task-by-task accounting showing every task from the three original roles and where it landed in the unified role (default.yml, Ubuntu_20.yml, Ubuntu_22.yml, or intentionally dropped with rationale)

**Acceptance criteria:**
1. Both syntax-check commands pass with exit code 0
2. list-tasks output shows the unified common role tasks resolving correctly
3. Diff audit document confirms no tasks were silently dropped

---

---

## Phase 2 — Unify the Desktop Role Family and Add Customization Foundation

**Purpose:** Merge `desktop`, `desktop-20.04`, and `desktop-22.04` into a single `desktop` role using the same dispatch pattern. Additionally, lay the foundation for directory-driven desktop customization: wallpaper rotation and per-site login screen configuration.

**Constraints and assumptions:**
- Depends on Phase 1 — unified `common` must exist before `desktop` can depend on it
- Desktop roles are 96% identical between 20.04 and 22.04 — most sub-task files (lubuntu.yml, lang.yml, sw.yml, etc.) should be shared with minimal version gating
- The 22.04 role on this branch represents the 24.04 target (forked and modernized for 24.04 upgrade path)
- `desktop-22.04` has the most complete/modern task set — it should be the base, with 20.04 differences extracted as version-specific overrides
- Wallpaper and login customization should be configuration-driven: group_vars set the images and interval, role reads from directories and variables, no hardcoded file lists in tasks
- Wallpapers are synced from a directory (`roles/desktop/files/wallpapers/`) — adding/removing images requires no task changes
- Login background is a single variable per site (`desktop_login_background`) in group_vars
- 16 Creative Commons / public domain California nature photos to be sourced for the wallpaper set
- Per-campus login images (anime girl, lotus, buddhist sticker) are existing assets — ARCHITECT should locate them in the current role files/ directories or ask DIRECTOR if not found
- ARCHITECT may choose the wallpaper rotation mechanism (cron + feh, variety, systemd timer, or similar) — pick what's lightest and most reliable on Lubuntu/LXQt
- If a sub-task file differs between desktop versions, ARCHITECT decides whether to use inline `when:` conditionals or version-specific task dispatch — use judgment based on divergence size

### Standing Permissions — Phase 2
- Specialists may create/edit files under `roles/desktop/`, `roles/.deprecated/`, `plays/`, `group_vars/`, and role `meta/main.yml` files only
- On ambiguous scope: conservative interpretation, note assumption, continue
- On interface ambiguity: specialist messages ARCHITECT; ARCHITECT resolves or escalates
- DIRECTOR may: choose implementation approach, choose wallpaper rotation mechanism, skip tasks with recorded rationale
- DIRECTOR may NOT: change phase definitions, add external dependencies not in SPRINT_PLAN.md

**Definition of done:**
- Single `desktop` role exists with same dispatch structure as unified `common`
- `meta/main.yml` depends on unified `common` (not `common-22.04`)
- Every sub-task file from all three old desktop roles accounted for (diff audit)
- Wallpaper rotation mechanism configured: reads all images from a synced directory, rotates on a configurable interval (`desktop_wallpaper_interval`)
- 16 California nature wallpaper images in `roles/desktop/files/wallpapers/` — Creative Commons or public domain, no watermarks
- Login background driven by `desktop_login_background` variable — defaults set, overridable per site in group_vars
- Group_vars examples added for at least one campus showing login background override
- `ansible-playbook plays/desktop.yml --syntax-check` passes
- `ansible-playbook plays/cs-lab-2404.yml --syntax-check` passes
- `ansible-playbook plays/cs-lab-2404.yml --list-tasks` shows correct task resolution
- All playbooks referencing `desktop-20.04` or `desktop-22.04` updated to use `desktop`
- Old roles moved to `roles/.deprecated/desktop-20.04/` and `roles/.deprecated/desktop-22.04/`

### Tasks — Phase 2

#### Task 2.1: Build unified desktop role structure with dispatch orchestrator
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending

Create the unified `roles/desktop/` role structure using the same Red Hat GPA dispatch pattern as unified `common`. The `desktop-22.04` role is the BASE — it becomes the shared/default task set. The old LXDE-era `desktop` role and `desktop-20.04` differences become version-specific overrides.

**Architecture decisions:**
- `tasks/main.yml` — orchestrator only (include_vars + first_found dispatch, identical pattern to `roles/common/tasks/main.yml`)
- `tasks/setup/default.yml` — the orchestrator for shared tasks. This replaces the old monolithic `main.yml`. It includes sub-task files (lubuntu.yml, lang.yml, lookandfeel.yml, sw.yml, etc.)
- Sub-task files live at `tasks/` level (e.g., `tasks/lubuntu.yml`, `tasks/lang.yml`) — they are included from default.yml
- `tasks/setup/Ubuntu_22.yml` — 22.04/24.04-specific tasks (WhiteSur theme install from lubuntu.yml, VSCode install)
- `tasks/setup/Ubuntu_20.yml` — 20.04-specific overrides (package `state: latest` → included inline via vars, `shell` command for pulseaudio enable)
- `vars/Ubuntu_20.yml` — 20.04-specific variable overrides (package lists, state preferences)
- `vars/Ubuntu_22.yml` — 22.04/24.04-specific variable overrides
- `defaults/main.yml` — merged defaults from all three roles (22.04 as base, add backward-compat vars)
- `handlers/main.yml` — from desktop-22.04 (restart pulseaudio, restart lightdm)
- `meta/main.yml` — depends on `common` (unified)

**Sub-task file strategy (what goes where):**

Shared sub-tasks (in `tasks/`, included from `tasks/setup/default.yml`):
- `lubuntu.yml` — shared LXQt package install (20.04/22.04 package list via vars `desktop_lubuntu_packages`); version-specific packages use `desktop_lubuntu_extra_packages` from vars/
- `lang.yml` — use 22.04 version as base (modern syntax); 20.04 differences are minimal (fcitx-qt4 vs qt5, hunspell-vi) — handle via vars `desktop_fcitx_packages`
- `lang-sanskrit.yml` — identical across 20.04/22.04, use 22.04 version
- `lookandfeel.yml` — use 22.04 version as base (LXQt paths, modern syntax with `loop:`, `notify:`, tags). The old LXDE-era role's lookandfeel is completely different and won't be carried forward (it targets Ubuntu 16.04/18.04 which are EOL)
- `sw.yml` — use 22.04 version as base. Version-specific software lists via vars `desktop_install_sw` and `desktop_remove_sw`
- `sw-office.yml` — use 22.04 version (identical to 20.04 functionally)
- `sw-browser.yml` — use 22.04 version (modern signed-by pattern). Old role's apt_key approach is deprecated
- `sw-goldendict.yml` — use 22.04 version (identical logic)
- `sw-vscode.yml` — from 22.04 only; gated by `when: vscode == true` (default true in 22.04, absent in 20.04 defaults → set false in vars/Ubuntu_20.yml)
- `sound.yml` — use 22.04 version (uses systemd module + notify handler)
- `app-menu.yml` — use 22.04 version (modern syntax, proper error handling)
- `wallpaper.yml` — NEW: wallpaper rotation setup (cron + feh)

Version-specific tasks:
- `tasks/setup/Ubuntu_22.yml` — WhiteSur GTK/icon/cursor theme install (from lubuntu.yml 22.04), ubuntu-desktop-minimal install
- `tasks/setup/Ubuntu_20.yml` — ubuntu-desktop-minimal install with `state: latest`, any 20.04-specific package adjustments

**Files/ directory:**
- Merge all files from desktop-22.04/files/ into desktop/files/ (superset)
- Keep files from desktop-20.04/files/ that aren't in 22.04 (they're identical)
- Move existing pics/ to files/pics/ (keep for login backgrounds)
- Create files/wallpapers/ directory (empty for now — Task 2.3 adds images)
- Keep config/, desktop-shortcuts/ as-is

**Templates/ directory:**
- Use all templates from desktop-22.04/templates/ (LXQt-era, modern)
- Drop old LXDE-era templates from desktop/ (lxpanel.j2 for LXDE path, lxsession.j2 for LXDE path, pcmanfm.j2 for LXDE path)

**Defaults (merged from all three roles):**
```yaml
# lightdm
lightdm_hide_users: false
lightdm_autologin_user: ""
lightdm_autologin_timeout: 0

# sw install
wpsoffice: false
libreoffice: true
openoffice: false
firefox: true
chrome: true
vscode: true
dropbox: false
skype: false

# look and feel
desktop_shortcuts: false
desktop_theme: WhiteSur
gtk_theme: WhiteSur
icon_theme: WhiteSur
pic_avatar: avatar-cttb.png
pic_bg: bg-windos10.jpg
start_icon: WhiteSur/scalable/places/start-here.svg
cursor_theme: WhiteSur-cursors

# hardware
dell_aio: true

# wallpaper rotation
desktop_wallpaper_interval: 900
desktop_wallpaper_dir: /usr/share/backgrounds/cttb

# login background (defaults to pic_bg for backward compat)
desktop_login_background: "{{ pic_bg }}"
```

**Cleanup:**
- Remove old cruft: `tasks/._main.yml`, `tasks/main.yml.1.*`, `tasks/main.yml.2.*`, `tasks/sw-browser.yml.0`, `tasks/sw-browser.yml.1.*`, `tasks/sw-office.yml.1.*`, `tasks/lang.yml.1`, `templates/lxsession.j2.0`, `templates/openbox-rc.j2.0`, `templates/pcmanfm.j2.0`

**Acceptance criteria:**
1. `roles/desktop/tasks/main.yml` contains ONLY include_vars + first_found dispatch (matches common role pattern)
2. `roles/desktop/tasks/setup/default.yml` includes all shared sub-task files in correct order
3. All sub-task files from 20.04/22.04 accounted for in the unified role
4. `roles/desktop/defaults/main.yml` contains merged defaults
5. `roles/desktop/handlers/main.yml` contains restart pulseaudio and restart lightdm
6. `roles/desktop/meta/main.yml` depends on `common`
7. `roles/desktop/vars/Ubuntu_20.yml` and `vars/Ubuntu_22.yml` exist
8. `roles/desktop/tasks/setup/Ubuntu_20.yml` and `Ubuntu_22.yml` exist
9. All templates from desktop-22.04 present in unified role
10. All files/ assets from desktop-22.04 present (config, pics, desktop-shortcuts)
11. No old backup/cruft files remain
12. `roles/desktop/files/wallpapers/` directory exists
13. `roles/desktop/tasks/wallpaper.yml` exists with cron + feh rotation

**Planning note:** Specialist should confirm understanding of the sub-task file strategy and dispatch pattern before implementing. This is a large task — focus on structural correctness, not content perfection.

---

#### Task 2.2: Wallpaper rotation and login background customization
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending (depends on 2.1)

Implement the wallpaper rotation mechanism and login background customization.

**Wallpaper rotation (cron + feh):**
- `tasks/wallpaper.yml` — included from `tasks/setup/default.yml`
- Installs `feh` package
- Syncs wallpaper images from `files/wallpapers/` to `{{ desktop_wallpaper_dir }}` on target (default: `/usr/share/backgrounds/cttb`)
- Creates a script `/usr/local/bin/rotate-wallpaper.sh` that:
  - Finds all `.jpg`/`.png` files in `{{ desktop_wallpaper_dir }}`
  - Picks one at random (using `shuf`)
  - Sets it as wallpaper via `feh --bg-fill`
- Adds a cron entry for all users via `/etc/cron.d/wallpaper-rotation`:
  - Runs every `{{ desktop_wallpaper_interval }}` seconds (convert to cron minutes: `desktop_wallpaper_interval // 60`)
  - Runs as each logged-in user (use `DISPLAY=:0` and detect active session)
- Templates the script and cron job

**Login background:**
- Update `templates/lightdm-gtk-greeter.j2` to use `{{ desktop_login_background }}` variable for the background image path
- The variable defaults to `{{ pic_bg }}` in defaults/main.yml for backward compatibility
- The image is deployed from `files/pics/{{ desktop_login_background }}` to the target path

**Group_vars updates:**
- Add `desktop_login_background` override to at least one campus group_vars file (e.g., `group_vars/dvgs` with `bg-dvgs.jpg`)
- Add `desktop_wallpaper_interval` example (commented) showing how to override

**Acceptance criteria:**
1. `feh` package is installed by wallpaper.yml
2. Wallpaper sync task copies all files from `files/wallpapers/` to target directory
3. Rotation script exists and picks random wallpaper
4. Cron job runs at configurable interval
5. `desktop_login_background` variable works in lightdm-gtk-greeter template
6. At least one group_vars file has `desktop_login_background` override
7. Default values in defaults/main.yml are set

---

#### Task 2.3: Source 16 California nature wallpaper images
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending (can run parallel with 2.1)

Download 16 high-resolution Creative Commons / public domain California nature photos for the wallpaper set.

**Requirements:**
- At least 1920x1080 resolution
- California landscapes: redwoods, coast, Sierra Nevada, wildflowers, Yosemite, Big Sur, Half Dome, Golden Gate, Death Valley, Joshua Tree, Mendocino coast, Point Reyes, Mt Shasta, Lake Tahoe, Channel Islands, Sequoia/Kings Canyon
- Creative Commons (CC0, CC-BY, CC-BY-SA) or public domain
- No watermarks, no copyright marks
- Sources: Unsplash, Pexels, Wikimedia Commons, Pixabay
- Save to `roles/desktop/files/wallpapers/`
- Name files descriptively: `california-redwoods-01.jpg`, `california-coast-big-sur.jpg`, etc.

**Acceptance criteria:**
1. 16 image files exist in `roles/desktop/files/wallpapers/`
2. All images are at least 1920x1080
3. File names are descriptive and consistent
4. No watermarks visible in images
5. Images are California nature scenes

**Note:** Since we cannot verify image content programmatically, the specialist should document the source URL and license for each image in a comment or the commit message.

---

#### Task 2.4: Deprecate old roles, update playbooks, and validate
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** pending (depends on 2.1, 2.2, 2.3)

Move old desktop roles to deprecated, update all playbook references, and run validation.

**Deliverables:**
- Move `roles/desktop-20.04/` to `roles/.deprecated/desktop-20.04/`
- Move `roles/desktop-22.04/` to `roles/.deprecated/desktop-22.04/`
- The original `roles/desktop/` has been overwritten by Task 2.1 — the old content is in git history. Move the old `desktop` to `roles/.deprecated/desktop-old/` BEFORE Task 2.1 runs (or Task 2.1 should handle preserving it)
  - NOTE: Task 2.1 will build the new role in-place at `roles/desktop/`, so the old LXDE content will be overwritten. This is acceptable since it's in git history.
- Update `plays/cs-lab-2404.yml`: change `desktop-22.04` to `desktop`
- Update comment in cs-lab-2404.yml: remove reference to "desktop-20.04 role"
- Verify all other playbooks already use `desktop` (unsuffixed)

**Validation:**
- `ANSIBLE_ROLES=./roles ansible-playbook plays/desktop.yml --syntax-check` passes
- `ANSIBLE_ROLES=./roles ansible-playbook plays/cs-lab-2404.yml --syntax-check` passes
- `ANSIBLE_ROLES=./roles ansible-playbook plays/cs-lab-2404.yml --list-tasks` shows correct task resolution

**Diff audit:**
- Produce a task-by-task accounting of every task from all three old desktop roles showing where each landed in the unified role (default.yml sub-tasks, Ubuntu_20.yml, Ubuntu_22.yml, or intentionally dropped with rationale)

**Acceptance criteria:**
1. `roles/.deprecated/desktop-20.04/` exists with all original files
2. `roles/.deprecated/desktop-22.04/` exists with all original files
3. `roles/desktop-20.04/` and `roles/desktop-22.04/` no longer exist
4. `plays/cs-lab-2404.yml` uses `desktop` role
5. Both syntax-check commands pass
6. list-tasks shows unified desktop role tasks resolving correctly
7. Diff audit confirms no tasks silently dropped

---

---

## Phase 3 — Inventory Cleanup

**Purpose:** Consolidate the inventory directory from its current state of accumulated snapshots and temp files into a clean, well-organized structure. The versioned backups (`hosts.1` through `hosts.7`), `.tmp` files, `.good` files, and `.to-sync-up-to` variants have served their purpose — git history preserves them. This is housekeeping that makes the repo easier to navigate after the structural refactor.

**Constraints and assumptions:**
- Independent of Phases 1 and 2 — no role changes, just inventory file organization
- The canonical inventory file is `inventory/hosts` — all other variants are historical snapshots
- `hosts_os_upgrade.ini` may still be relevant if it tracks hosts pending upgrade — ARCHITECT should check its contents before removing
- Do not change group structure, host membership, or variable assignments — this is file cleanup only, not inventory redesign
- Git history preserves all removed files — nothing is permanently lost
- ARCHITECT may reorganize the directory structure (e.g., separating static inventory from dynamic) if it improves clarity, but must not change any group names or host assignments that playbooks depend on

### Standing Permissions — Phase 3
- Specialists may create/edit files under `inventory/` only
- On ambiguous scope: conservative interpretation, note assumption, continue
- DIRECTOR may: decide which files are snapshots vs genuinely different configurations

**Definition of done:**
- `inventory/` contains only the canonical `hosts` file (and `hosts_os_upgrade.ini` if still relevant)
- All historical snapshot files (`hosts.1` through `hosts.7`, `.tmp`, `.good`, `.to-sync-up-to`) removed
- `ansible-inventory --list` produces the same output before and after cleanup (no functional change)
- Any inventory files that are genuinely different configurations (not snapshots) are documented with a comment or README

### Analysis Notes — Phase 3

**File classification (ARCHITECT analysis):**
- `inventory/hosts` — CANONICAL. Primary INI inventory. Most current host list.
- `inventory/hosts.1` — SNAPSHOT. Oldest version. Uses `ansible_ssh_user` (deprecated), fewer hosts, missing LXC entries.
- `inventory/hosts.2.tmp` — SNAPSHOT. Temp file with inline IP override for rui-test1.
- `inventory/hosts.3` — SNAPSHOT. Intermediate version, missing several hosts present in canonical.
- `inventory/hosts.5.good` — SNAPSHOT. Similar to hosts.3, marked "good" at some point.
- `inventory/hosts.6.to-sync-up-to` — SNAPSHOT. Development variant with some renamed hosts and extra entries.
- `inventory/hosts.7` — SNAPSHOT. Close to canonical but with some host renames and missing entries.
- `inventory/hosts_os_upgrade.ini` — DIFFERENT CONFIGURATION. Flat list of hosts with MAC addresses and IP addresses for PXE/OS upgrade deployment. Completely different format and purpose from the main inventory. Still relevant for ongoing Ubuntu upgrade work.

**Pre-existing issue:** `host_vars/srv-gw` line 87 contains a tab character, causing `ansible-inventory --list` to fail with "YAML parsing failed: Tabs are usually invalid in YAML." This is outside Phase 3 scope (host_vars, not inventory files). Validation will use `ansible-inventory -i inventory/hosts --graph` or verify the inventory INI parsing succeeds independently.

### Tasks — Phase 3

#### Task 3.1: Remove snapshot files and validate
**Specialist:** jacob (Infrastructure & DevOps)
**Status:** complete

Remove all historical snapshot/backup inventory files, keeping only the canonical `hosts` and the still-relevant `hosts_os_upgrade.ini`.

**Deliverables:**
- Remove `inventory/hosts.1`
- Remove `inventory/hosts.2.tmp`
- Remove `inventory/hosts.3`
- Remove `inventory/hosts.5.good`
- Remove `inventory/hosts.6.to-sync-up-to`
- Remove `inventory/hosts.7`
- Add a header comment to `inventory/hosts_os_upgrade.ini` documenting its purpose (PXE/OS upgrade target list with MAC addresses)
- Verify `inventory/` contains only: `hosts`, `hosts_os_upgrade.ini`, `group_vars` symlink, `host_vars` symlink

**Validation:**
- `ANSIBLE_ROLES_PATH=./roles ansible-inventory -i inventory/hosts --graph` produces valid group/host graph (note: `--list` fails due to pre-existing tab in `host_vars/srv-gw`, outside scope)
- No functional change to inventory structure

**Acceptance criteria:**
1. Only `hosts`, `hosts_os_upgrade.ini`, `group_vars` symlink, and `host_vars` symlink remain in `inventory/`
2. All 6 snapshot files are removed (git history preserves them)
3. `hosts_os_upgrade.ini` has a descriptive header comment explaining its purpose
4. `ansible-inventory -i inventory/hosts --graph` succeeds
5. No changes to the canonical `hosts` file content
