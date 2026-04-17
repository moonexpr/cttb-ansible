# Refactor Plan: cttb-ansible

Multi-phase plan for refactoring the CTTB Ansible infrastructure repo. Each phase is independently deployable and testable. Phases are ordered by dependency — later phases build on earlier ones.

**Guiding principles (from Red Hat GPA + Ansible community):**
- One role per function, parameterized by OS version — never fork roles per release
- Platform-specific variables in `vars/{Distribution}_{Major}.yml`, loaded via `include_vars` loop
- Platform-specific tasks in `tasks/setup/{Distribution}_{Major}.yml`, loaded via `first_found`
- `main.yml` orchestrates includes only — no inline tasks
- All role variables namespaced with role prefix
- Data (variable values) lives in inventory, not in roles

---

## Phase 1: Unify the `common` Role Family

**Goal:** Merge `common`, `common-20.04`, and `common-22.04` into a single `common` role that handles all Ubuntu versions via variable/task dispatch.

**Why first:** The `common` role is a dependency of both `desktop` and `server` roles. Unifying it establishes the dispatch pattern that all subsequent phases reuse.

### Tasks

#### 1.1 — Diff and classify task divergence

Produce a line-by-line comparison of `common/tasks/main.yml` (302 lines), `common-20.04/tasks/main.yml` (300 lines), and `common-22.04/tasks/main.yml` (253 lines). Classify each task as:
- **Shared** — identical or trivially equivalent across all three
- **Version-gated** — same intent but different package names, paths, or service names
- **Version-exclusive** — only applies to one Ubuntu release

Deliverable: a classification table saved to `.claude/plans/common-task-classification.md`.

**Acceptance criteria:**
- Every task in all three files is classified
- Version-gated tasks have the specific variable differences identified (e.g., package name X on 20.04, package name Y on 22.04)

#### 1.2 — Create the platform dispatch structure

Build the unified `common` role structure:

```
roles/common/
├── tasks/
│   ├── main.yml              # orchestrator (include_vars + include_tasks only)
│   ├── setup/
│   │   ├── default.yml        # shared tasks (from classification: "shared")
│   │   ├── Ubuntu_20.yml      # 20.04-exclusive tasks
│   │   └── Ubuntu_22.yml      # 22.04-exclusive tasks
│   └── (component task files as needed)
├── defaults/main.yml          # user-overridable defaults, namespaced common_*
├── vars/
│   ├── main.yml               # shared internal vars
│   ├── Ubuntu_20.yml           # 20.04-specific vars (package names, paths)
│   └── Ubuntu_22.yml           # 22.04-specific vars
├── handlers/main.yml
├── templates/
└── files/
```

The `tasks/main.yml` pattern:

```yaml
---
- name: Set platform/version specific variables
  include_vars: "{{ __common_vars_file }}"
  loop:
    - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_major_version'] }}.yml"
  vars:
    __common_vars_file: "{{ role_path }}/vars/{{ item }}"
  when: __common_vars_file is file

- name: Run shared tasks
  include_tasks: "{{ role_path }}/tasks/setup/default.yml"

- name: Run platform-specific tasks
  include_tasks: "{{ lookup('first_found', __common_ff) }}"
  vars:
    __common_ff:
      files:
        - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_major_version'] }}.yml"
        - default.yml
      paths:
        - "{{ role_path }}/tasks/setup"
```

**Acceptance criteria:**
- Single `common` role handles 20.04 and 22.04 hosts correctly
- No task duplication between version files — shared logic lives in `default.yml` only
- Version-gated tasks use variables from `vars/Ubuntu_XX.yml`, not inline conditionals
- All files from `common-20.04/files/` and `common-22.04/files/` merged into `common/files/`
- All templates merged (they're identical across versions)
- Handlers merged (they're identical across versions)

#### 1.3 — Update consumers and remove old roles

- Update `roles/desktop-22.04/meta/main.yml` dependency from `common-22.04` → `common`
- Update `roles/desktop-20.04/meta/main.yml` dependency from `common-20.04` → `common` (if it exists)
- Update any playbooks that directly reference `common-20.04` or `common-22.04`
- Rename old roles to `common-20.04.deprecated/` and `common-22.04.deprecated/` (do not delete yet — keep as reference until Phase 1 is validated)
- Update `plays/base.yml` if needed

**Acceptance criteria:**
- `grep -r 'common-20.04\|common-22.04' plays/ roles/` returns zero hits (excluding .deprecated dirs)
- `ansible-playbook plays/cs-lab-2404.yml --check` runs without errors on a test host
- The deprecated role directories exist but are not referenced

#### 1.4 — Extend to Ubuntu 24.04

Add `vars/Ubuntu_24.yml` and `tasks/setup/Ubuntu_24.yml` for 24.04 support. This validates the dispatch pattern — adding a new version should require zero changes to existing task files.

**Acceptance criteria:**
- Adding 24.04 support only required creating 2 new files (vars + tasks)
- No existing files were modified
- `cs-lab-2404.yml` playbook works against 24.04 hosts

---

## Phase 2: Unify the `desktop` Role Family

**Goal:** Merge `desktop`, `desktop-20.04`, and `desktop-22.04` into a single `desktop` role using the same dispatch pattern from Phase 1.

**Why second:** Depends on Phase 1 (unified `common` role as dependency). The desktop roles are 96% identical between 20.04 and 22.04, making this the highest-DRY-payoff phase.

### Tasks

#### 2.1 — Diff and classify desktop task divergence

Same approach as 1.1. The desktop role is already well-decomposed into sub-task files (lubuntu.yml, lang.yml, lookandfeel.yml, sw.yml, etc.), so classification should map at the sub-task-file level:
- Which sub-task files are identical across versions?
- Which have version-specific differences (and what are they)?
- Which are version-exclusive?

Also classify templates and defaults differences.

Deliverable: `.claude/plans/desktop-task-classification.md`

**Acceptance criteria:**
- Every sub-task file, template, and default classified
- The 4% divergence between desktop-20.04 and desktop-22.04 is precisely identified

#### 2.2 — Create unified desktop role with dispatch

Build the unified structure. Since the desktop role already uses `include_tasks` for sub-components, the dispatch can happen at the component level where versions diverge:

```
roles/desktop/
├── tasks/
│   ├── main.yml               # orchestrator
│   ├── lubuntu.yml            # shared
│   ├── lang.yml               # shared (or with version dispatch inside)
│   ├── lang-sanskrit.yml      # shared
│   ├── lookandfeel.yml        # may need version-specific sections
│   ├── app-menu.yml           # shared
│   ├── sw.yml                 # shared orchestrator
│   ├── sw-office.yml          # shared
│   ├── sw-browser.yml         # shared
│   ├── sw-vscode.yml          # shared
│   ├── sw-goldendict.yml      # shared
│   ├── sound.yml              # shared
│   └── setup/                 # version-specific overrides
│       ├── Ubuntu_20.yml
│       └── Ubuntu_22.yml
├── defaults/main.yml          # merged defaults, namespaced desktop_*
├── vars/
│   ├── main.yml
│   ├── Ubuntu_20.yml
│   └── Ubuntu_22.yml
├── handlers/main.yml
├── templates/                 # merged templates
├── files/                     # merged files
└── meta/main.yml              # depends on: common (unified)
```

**Acceptance criteria:**
- Single `desktop` role handles both 20.04 and 22.04
- Sub-task files that are shared contain no version conditionals
- Version-specific behavior isolated to `vars/Ubuntu_XX.yml` and minimal `setup/Ubuntu_XX.yml` tasks
- `meta/main.yml` depends on unified `common` role
- All templates, files, defaults merged with version-specific values in vars

#### 2.3 — Update playbooks and remove old roles

- All playbooks referencing `desktop-20.04` or `desktop-22.04` updated to use `desktop`
- `cs-lab-2404.yml` updated: `desktop-22.04` → `desktop`
- Old roles renamed to `.deprecated/`

**Acceptance criteria:**
- `grep -r 'desktop-20.04\|desktop-22.04' plays/ roles/` returns zero hits
- All desktop playbooks pass `--check` on test hosts

#### 2.4 — Extend to Ubuntu 24.04

Same as 1.4 — add `vars/Ubuntu_24.yml` and `tasks/setup/Ubuntu_24.yml`. Validate the pattern holds for the desktop role's more complex structure.

**Acceptance criteria:**
- 24.04 desktop support requires only new vars/tasks files
- No modification to shared task files

---

## Phase 3: Decompose the `common` God Role

**Goal:** Break the unified `common` role into focused function-roles, with `common` as a thin aggregator that includes them.

**Why third:** Depends on Phase 1 (unified common role). Decomposing a still-forked role would triple the work. The unified role from Phase 1 is the starting point.

**Scope note:** This phase is the most architecturally significant. The current `common` role handles 20+ unrelated concerns across ~300 lines. Each concern should be independently applicable, testable, and skippable.

### Tasks

#### 3.1 — Identify function boundaries

Review the unified `common` role from Phase 1 and group tasks into cohesive functions. Expected functions (to be validated during analysis):

| Function | Responsibility | Approximate task count |
|----------|---------------|----------------------|
| `base-packages` | Core apt packages, repos, sources.list | 8-10 |
| `dns-client` | resolv.conf, DNS settings | 2-3 |
| `ntp-client` | NTP/timesyncd configuration | 2-3 |
| `ssh-config` | SSH server/client config, keys | 3-5 |
| `locale` | Locale, timezone, keyboard | 3-4 |
| `sysctl` | Kernel parameters, IPv6 disable | 2-3 |

Deliverable: function boundary map with task-to-function assignments.

**Acceptance criteria:**
- Every task assigned to exactly one function
- Each function has a single, nameable responsibility
- No function has fewer than 2 tasks (avoid over-decomposition)

#### 3.2 — Extract function-roles

For each function identified in 3.1, create a role:

```
roles/base-packages/
├── tasks/main.yml
├── defaults/main.yml       # namespaced: base_packages_*
├── vars/
│   ├── Ubuntu_20.yml
│   └── Ubuntu_22.yml
└── handlers/main.yml       # if needed

roles/dns-client/
├── tasks/main.yml
├── defaults/main.yml       # namespaced: dns_client_*
└── ...
```

Each function-role uses the same platform dispatch pattern from Phase 1.

**Acceptance criteria:**
- Each function-role is independently includable via `include_role`
- Each function-role has namespaced variables (no collision with other roles)
- Each function-role has its own defaults with documented parameters

#### 3.3 — Rewrite `common` as aggregator

The `common` role becomes a thin orchestrator:

```yaml
# roles/common/tasks/main.yml
---
- name: Base packages
  include_role:
    name: base-packages
  tags: [common, base-packages]

- name: DNS client
  include_role:
    name: dns-client
  tags: [common, dns-client]

- name: NTP client
  include_role:
    name: ntp-client
  tags: [common, ntp-client]

# ... etc
```

**Acceptance criteria:**
- `common` role contains no inline tasks — only `include_role` statements
- Running `common` produces identical results to pre-decomposition
- Individual functions are skippable via `--skip-tags`
- `desktop` and `server` roles still depend on `common` and work unchanged

#### 3.4 — Validate backward compatibility

- All existing playbooks work unchanged (they reference `common` or roles that depend on it)
- `ansible-playbook plays/cs-lab-2404.yml --check` passes
- `ansible-playbook plays/gw.yml --check` passes
- Tag-based partial runs work: `ansible-playbook plays/base.yml --tags dns-client`

**Acceptance criteria:**
- Zero playbook modifications required
- All existing group_vars/host_vars continue to work
- Function-roles can be used independently in new playbooks

---

## Phase 4: Parameterized Software Installation

**Goal:** Replace ad-hoc software install playbooks with a reusable pattern.

**Independent of Phases 1-3.** Can be executed in parallel.

### Context

Currently 8 one-off install playbooks in `plays/` follow three patterns:
1. **apt install** — `dvgs-install-unikey.yml` (3 lines of tasks)
2. **tarball download + unpack** — `dvgs-install-vscode.yml`, `dvgs-install-python3.13.yml` (shell one-liners)
3. **pip install** — `igdvs-install-pip.yml`

The tarball pattern is the most concerning — long shell one-liners with hardcoded URLs, no idempotency, no error handling.

### Tasks

#### 4.1 — Create `software-install` role

A parameterized role that supports the common installation patterns:

```yaml
# roles/software-install/defaults/main.yml
---
software_install_packages: []        # list of apt packages
software_install_tarballs: []        # list of {url, dest, creates}
software_install_remove_snaps: []    # list of snap packages to remove first
```

The role handles:
- Snap removal (when migrating from snap to apt/tarball)
- APT package installation
- Tarball download + extraction (with `creates:` for idempotency)
- Desktop file installation

**Acceptance criteria:**
- Role is idempotent (second run reports no changes)
- Supports all three current installation patterns
- Variables are namespaced `software_install_*`
- No shell one-liners — uses `apt`, `get_url`, `unarchive` modules

#### 4.2 — Migrate existing install playbooks

Convert each ad-hoc playbook to use the new role. For example:

```yaml
# plays/dvgs-install-vscode.yml (after)
---
- hosts: dvgs_cs_lab:dvgs_koha
  roles:
    - role: software-install
      vars:
        software_install_tarballs:
          - url: "http://apt.cttb/it/code-stable-x64-1723659430.tar"
            dest: /opt/vscode
            creates: /opt/vscode/bin/code
        software_install_desktop_files:
          - url: "http://apt.cttb/it/vscode.desktop"
            dest: /usr/share/applications/vscode.desktop
```

**Acceptance criteria:**
- All 8 install playbooks converted
- Original shell commands replaced with proper Ansible modules
- Each install is idempotent
- Existing functionality preserved

#### 4.3 — Consider group_vars-driven approach

Evaluate whether software lists should live in group_vars instead of per-playbook vars. For sites that always install the same software set, this eliminates the need for separate install playbooks entirely — the desktop role's `sw.yml` could read `desktop_additional_software` from group_vars.

Deliverable: recommendation document. This may or may not result in code changes depending on how the campus software needs actually vary.

**Acceptance criteria:**
- Written recommendation with pros/cons
- If adopted: group_vars updated, install playbooks retired or simplified

---

## Phase 5: Variable Contracts and Namespacing

**Goal:** Make role interfaces explicit via `argument_specs`, namespace all variables, and document the variable hierarchy.

**Independent of Phases 1-3** but should run after them (since Phases 1-3 will change variable names).

### Tasks

#### 5.1 — Audit and namespace all role variables

For every role, ensure:
- All defaults are prefixed with the role name (e.g., `common_disable_ipv6`, not `disable_ipv6`)
- Internal variables use double-underscore prefix (`__common_platform_packages`)
- Registered variables are namespaced (`__common_apt_result`, not `apt_result`)
- Tags are prefixed with role name

Deliverable: variable rename map (old name → new name) for each role.

**Acceptance criteria:**
- Zero unprefixed variables in any role's defaults/
- All registered variables namespaced
- group_vars and host_vars updated to match new variable names

#### 5.2 — Add argument_specs

For each role, create `meta/argument_specs.yml` declaring:
- Required variables (no default)
- Optional variables (with default and description)
- Variable types (str, list, dict, bool)

Example:
```yaml
# roles/common/meta/argument_specs.yml
argument_specs:
  main:
    short_description: Base OS configuration
    options:
      common_disable_ipv6:
        type: bool
        default: true
        description: Disable IPv6 via sysctl
      common_additional_packages:
        type: list
        elements: str
        default: []
        description: Extra apt packages to install beyond the base set
```

**Acceptance criteria:**
- Every role has `meta/argument_specs.yml`
- Running with `ANSIBLE_ACTION_WARNINGS=True` produces no undefined-variable warnings
- `ansible-doc -t role common` shows the role's interface

#### 5.3 — Document the variable hierarchy

Create a `docs/variables.md` (or update `PROJECT.md`) with:
- The full variable precedence chain for this repo
- Which variables are set at each level (role defaults → group_vars/all → group_vars/{site} → host_vars)
- A table of all cross-role variable dependencies (role X consumes variable Y defined in group_vars Z)

**Acceptance criteria:**
- A new contributor can understand where to set a variable by reading this document
- All implicit cross-role variable dependencies are documented

---

## Phase 6: Netinstall Unification (Optional)

**Goal:** Merge `netinstall` and `netinstall-2404` into a single role.

**Why optional:** Unlike common/desktop, these roles have a justified 85% divergence — `netinstall` uses preseed (Debian installer) while `netinstall-2404` uses autoinstall (Subiquity). The underlying installation technology genuinely changed. Unification is possible but the benefit is lower.

### Tasks

#### 6.1 — Evaluate unification value

The preseed vs. autoinstall split is a real technology boundary. Determine whether:
- Both systems will coexist long-term (some hosts stay on 20.04/22.04)
- 24.04+ is the future and preseed will be retired
- A unified role with a `netinstall_method: preseed|autoinstall` variable makes sense

Deliverable: decision document.

#### 6.2 — Unify if warranted

If unification is chosen, apply the same pattern: single role, `vars/` and `tasks/setup/` dispatch by method or Ubuntu version.

**Acceptance criteria:**
- PXE boot menu generation works for both preseed and autoinstall hosts
- ISO management works for both
- Preseed and autoinstall template generation isolated to version-specific task files

---

## Phase Dependencies

```
Phase 1 (common unification)
    ↓
Phase 2 (desktop unification) — depends on Phase 1
    ↓
Phase 3 (common decomposition) — depends on Phase 1
    
Phase 4 (software install) — independent, can parallel with 1-3
Phase 5 (variable contracts) — should follow Phases 1-3
Phase 6 (netinstall) — independent, optional
```

**Recommended execution order:** 1 → 2 & 4 in parallel → 3 → 5 → 6 (if desired)

---

## Validation Strategy

Each phase should be validated by:

1. **Syntax check:** `ansible-playbook plays/<playbook>.yml --syntax-check` for all affected playbooks
2. **Dry run:** `ansible-playbook plays/<playbook>.yml --check --diff` against a test host (dvgs-lab3 or equivalent)
3. **Incremental deploy:** Apply to one lab machine, verify behavior, then roll out to a group
4. **Regression:** Confirm that unmodified playbooks (e.g., `gw.yml`, `server.yml`) still work

No phase should be merged to main until its validation passes on at least one real host per Ubuntu version.

---

## Cleanup (After All Phases)

- Delete `.deprecated/` role directories
- Delete `.claude/plans/common-task-classification.md` and `desktop-task-classification.md`
- Delete `.claude/plans/cttb-ansible-domain-analysis.md`
- Update `CLAUDE.md` and `PROJECT.md` with new role structure
- Update `README.md` role inventory
