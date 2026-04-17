# Domain Analysis: cttb-ansible

Ansible infrastructure management for CTTB (City of Ten Thousand Buddhas) — a multi-campus environment spanning DVBS, DVGS, and DRBU with Ubuntu desktops, servers, and network infrastructure.

---

## Subsystem Map

| Subsystem | Directories / Roles | Domain Concept |
|-----------|-------------------|----------------|
| **OS Foundation** | `common`, `common-20.04`, `common-22.04` | Base OS config: packages, repos, DNS, NTP, locale, IPv6 |
| **Desktop Environment** | `desktop`, `desktop-20.04`, `desktop-22.04` | Lubuntu desktop: theme, shortcuts, software, localization |
| **Server Foundation** | `server` | Server-specific base (depends on `common`) |
| **Network Services** | `dhcpd`, `unbound`, `time-server`, `firehol`, `squid`, `e2guardian` | DHCP, DNS, NTP, firewall, proxy, content filtering |
| **Identity & Auth** | `ldap-server`, `ldap-client`, `cttb-ca-client` | LDAP auth, PKI certificates |
| **Storage** | `nfs-home`, `zfs` | NFS home dirs, ZFS filesystems |
| **Provisioning** | `netinstall`, `netinstall-2404`, `debmirror` | PXE boot, preseed/autoinstall, package mirroring |
| **Applications** | `asterisk`, `cups-server`, `cups-client`, `koha`, `git` | VoIP, printing, library ILS, git hosting |
| **Hardware** | `ups`, `hp-procurve`, `virt` | UPS power, network switches, KVM/LXD |
| **Orchestration** | `plays/` (40+ playbooks) | Site-specific deployment compositions |
| **Configuration Data** | `group_vars/`, `host_vars/`, `inventory/` | Per-site, per-group, per-host parameterization |
| **Custom Modules** | `library/ntc/`, `roles/cups-server/library/` | NTC network toolkit, CUPS printer admin |

---

## Creational Relationships

### How "objects" (configured hosts) are created

In Ansible's paradigm, roles are the unit of reusable behavior (analogous to classes), playbooks are the composition point (analogous to factories), and the inventory + variable hierarchy is the configuration injection mechanism (analogous to DI).

**Current creation patterns:**

1. **Version-forked roles (anti-pattern: Parallel Class Hierarchies).** Rather than parameterizing OS version as a variable, entire role trees are duplicated per Ubuntu release:
   - `common` → `common-20.04` → `common-22.04`
   - `desktop` → `desktop-20.04` → `desktop-22.04`
   - `netinstall` → `netinstall-2404`

   Each fork starts as a copy, diverges slightly, and accumulates drift. The desktop-20.04 and desktop-22.04 roles are **96.2% identical**. This means adding a new Ubuntu version (e.g., 26.04) requires forking yet another copy of each role.

2. **Playbook-as-factory.** Playbooks compose roles for specific deployment contexts (e.g., `dvgs-cs-lab.yml` applies `common-22.04` + `desktop-22.04` with cs-lab group_vars). This is a reasonable **Factory Method** analog — the playbook selects which concrete roles to apply based on the deployment target. However, the factories themselves are sometimes duplicated rather than parameterized.

3. **One-off install playbooks (ad-hoc creation).** Software installation playbooks like `dvgs-install-vscode.yml`, `dvgs-install-python3.13.yml`, `dvgs-install-unikey.yml` are standalone scripts that could be parameterized into a single role with a variable-driven package list. They follow identical patterns (snap removal + apt install) with only the package name varying.

**Missing patterns:**
- **No Abstract Factory or Builder for version-gated roles.** A single role with OS-version conditionals (`when: ansible_distribution_release == 'jammy'`) would eliminate the parallel hierarchy.
- **No parameterized "software installer" role** — each software install is a separate playbook instead of a reusable abstraction.

---

## Structural Relationships

### Dependency directions

```
Playbooks (orchestrators)
  └── Roles (behavior units)
        ├── meta/main.yml dependencies (explicit)
        │     desktop-22.04 → common-22.04
        │     desktop-20.04 → common-20.04
        │     server → common
        │     unbound → server → common
        └── Variable references (implicit)
              └── group_vars/all (global config)
              └── group_vars/{site} (site-specific)
              └── host_vars/{host} (host-specific)
```

### Structural observations

1. **Shallow dependency tree.** Most roles have 0-1 explicit dependencies. This is both a strength (low coupling) and a weakness (implicit dependencies are invisible).

2. **Facade pattern (partial).** The `desktop-22.04` role acts as a Facade — its `tasks/main.yml` orchestrates 10+ sub-task files (lubuntu.yml, lang.yml, lookandfeel.yml, sw.yml, etc.). This is the best-structured role in the repo. Most other roles are monolithic single-file tasks.

3. **No Composite pattern for multi-site deployment.** Each site (DVBS, DVGS, DRBU) has its own playbooks and group_vars, but there's no compositional abstraction — a "site" is implicitly defined by the intersection of inventory groups and group_vars files rather than as an explicit first-class concept.

4. **Template coupling.** Templates reference variables from group_vars and role defaults without a clear contract. For example, `firehol.j2` depends on variables from multiple scopes, making the template's input contract implicit.

---

## Behavioral Relationships

### Communication mechanisms

1. **Variable cascade (primary).** Subsystems communicate through Ansible's variable precedence: role defaults → group_vars/all → group_vars/{group} → host_vars/{host}. This is effectively a **Chain of Responsibility** for configuration — each level can override or extend values from the level below.

2. **Handler notification (event-like).** Roles use `notify:` to trigger handlers (restart services, reload configs). This is a limited **Observer** pattern scoped within each role. There are no cross-role handler notifications — handlers are always role-scoped.

3. **Sequential role execution (Pipeline).** Playbooks execute roles in sequence. Role dependencies (meta/main.yml) enforce ordering. This is a simple **Pipes and Filters** architecture where each role transforms the host state.

4. **No Mediator.** Cross-role coordination relies entirely on variable state left behind by prior roles. If role A sets a fact that role B needs, the dependency is invisible unless explicitly documented.

### Coupling mechanisms

- **Global variable coupling (HIGH).** `ansible_assets_url` is consumed by 7+ roles. Any change to the assets server URL propagates across the entire infrastructure.
- **Site-specific variable coupling (MEDIUM).** Each site's group_vars defines `ldap_groups`, `cups_default_queue`, `nfs_homes_host` — consumed by identity, printing, and storage roles respectively.
- **Inventory coupling (LOW).** Roles are host-group-agnostic; they operate on whatever hosts the playbook targets.

---

## Principle Assessment

### SRP (Single Responsibility)
- **Upheld:** Most roles have a single, clear responsibility (dhcpd manages DHCP, cups-server manages printing).
- **Violated:** The `common-*` roles are catch-all "base configuration" with 20+ tasks spanning packages, repos, DNS, NTP, SSH, locale, IPv6, and more. These have multiple reasons to change.

### OCP (Open-Closed)
- **Severely violated by version-forked roles.** Adding support for Ubuntu 24.04 desktops requires creating an entirely new `desktop-24.04` role rather than extending the existing one. The current structure is closed for extension — you must modify (or duplicate) to add new OS versions.
- **Partially upheld** by the variable override system — group_vars allow per-site customization without modifying roles.

### LSP (Liskov Substitution)
- **Violated across version forks.** `common-20.04` and `common-22.04` are not substitutable for each other despite serving the same conceptual role. They share ~27.5% task overlap with divergent implementations for the rest. A playbook written for one cannot swap in the other.

### DIP (Dependency Inversion)
- **Partially upheld.** Roles depend on variables (abstractions) rather than hard-coded values. However, the variable contracts are implicit — no role explicitly declares "I require these variables to be set."
- **Violated** by hard-coded OS-specific logic within version-forked roles instead of abstracting behind conditionals.

### ISP (Interface Segregation)
- **Violated by group_vars/all.** All roles see all global variables, even those irrelevant to them. A desktop role sees network install variables (`ni_*`), firewall variables, etc.

### High Cohesion (GRASP)
- **Strong** in focused roles (dhcpd, cups-server, firehol).
- **Weak** in common-* roles (catch-all base config) and desktop-* roles (theme + software + localization + shortcuts all in one role, though mitigated by sub-task decomposition).

### Low Coupling (GRASP)
- **Generally good** — roles are loosely coupled through variables rather than direct references.
- **Weakened** by the 7-role dependency on `ansible_assets_url` and implicit variable contracts.

### Protected Variations (GRASP)
- **Severely violated.** The OS version is the primary variation point in this infrastructure, yet it is not encapsulated behind an abstraction. Instead, entire role hierarchies are forked per OS version, exposing every consumer to the variation.

### Common Closure Principle (CCP)
- **Violated.** When Ubuntu version changes, you must modify multiple roles (`common-*`, `desktop-*`, `netinstall-*`) and create new playbooks. These should be grouped so a version change touches one place.

### Acyclic Dependencies (ADP)
- **Upheld.** No circular dependencies detected. The dependency graph is a clean DAG.

---

## Findings Summary

Ranked by severity (impact on maintainability, change amplification, and rigidity):

### 1. Parallel Role Hierarchies — Version Forking (CRITICAL)

- **Design smell:** Parallel class hierarchies. Three generations of `common` (unsuffixed, -20.04, -22.04) and `desktop` (unsuffixed, -20.04, -22.04) roles with 27-96% overlap.
- **Principles violated:** OCP (not extensible to new versions), Protected Variations (version not encapsulated), CCP (version change touches N roles), LSP (versions not substitutable).
- **Candidate pattern:** **Strategy** — extract OS-version-specific behavior into conditional task blocks or version-specific variable files within a single role. The role becomes the Context; version-specific task includes become ConcreteStrategies selected by `ansible_distribution_version`.
- **Severity:** CRITICAL. Every Ubuntu upgrade requires forking 3+ roles and all associated playbooks. This is the primary source of maintenance burden and the repo's most painful change amplification vector. Desktop-20.04 and desktop-22.04 are 96% identical — nearly all the duplication is accidental.

### 2. God Role — common-* as Catch-All (HIGH)

- **Design smell:** God class / low cohesion. The `common-*` roles handle packages, repositories, DNS, NTP, SSH config, locale, IPv6, kernel parameters, and more — 20+ tasks spanning unrelated concerns.
- **Principles violated:** SRP (multiple reasons to change), High Cohesion (unrelated responsibilities grouped together).
- **Candidate pattern:** **Facade + Module decomposition** — decompose `common-*` into focused sub-roles (e.g., `base-packages`, `dns-client`, `ntp-client`, `ssh-config`) with `common` as a Facade that includes them all for backward compatibility. Each sub-role becomes independently reusable and testable.
- **Severity:** HIGH. Any change to DNS config risks breaking NTP setup due to shared variable scope. Testing a locale change requires running the entire common role.

### 3. Ad-Hoc Software Installation — Missing Abstraction (MEDIUM)

- **Design smell:** Duplicated code / missing abstraction. Software install playbooks (`dvgs-install-vscode.yml`, `dvgs-install-python3.13.yml`, `dvgs-install-unikey.yml`) follow identical patterns with only package names varying.
- **Principles violated:** DRY, Information Expert (the pattern knowledge is scattered across files instead of centralized).
- **Candidate pattern:** **Template Method** — create a parameterized `software-install` role with a standard algorithm (remove snaps → add repos → install packages → configure). Each software install becomes a variable-driven invocation rather than a separate playbook.
- **Severity:** MEDIUM. Each new software request creates a new file instead of a one-line variable addition. Manageable at current scale but increasingly painful.

### 4. Implicit Variable Contracts (MEDIUM)

- **Design smell:** Hidden dependencies / invisible coupling. Roles consume variables (e.g., `ansible_assets_url`, `ldap_groups`, `cups_default_queue`) without declaring them. The "interface" between roles and their configuration is undocumented.
- **Principles violated:** DIP (no explicit abstraction boundary), Protected Variations (consumers coupled to variable naming).
- **Candidate pattern:** **Specification** (adapted) — define explicit variable contracts in each role's `defaults/main.yml` with documented defaults and `assert` tasks that validate required variables are set. This makes the role's input interface explicit and fails fast on misconfiguration.
- **Severity:** MEDIUM. Currently works because one person (JC) knows the variable landscape. Fragile for onboarding or handoff.

### 5. Site Configuration Sprawl (LOW)

- **Design smell:** Shotgun surgery. Adding a new campus site requires creating group_vars files, inventory entries, and playbooks in multiple locations with no template or guide.
- **Principles violated:** CCP (site addition touches many directories), Creator (no single point responsible for site creation).
- **Candidate pattern:** **Builder** (adapted) — create a site template/skeleton that generates the required group_vars, inventory entries, and playbook from a site definition. Or use an inventory plugin that derives group structure from a single configuration source.
- **Severity:** LOW. Sites are added rarely. Current approach works but is error-prone.
