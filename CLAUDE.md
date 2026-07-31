# CLAUDE.md

Project rules for `cttb-ansible`.

> **This file is self-contained.** It embeds the operational rules a sysadmin
> needs, so the repo works on any clone without a global Claude framework
> installed. (On machines that also carry the operator's `~/.claude/CLAUDE.md`,
> that framework loads too and is consistent with what's here — but nothing
> below depends on it.)

> The `.claude/` sysadmin toolkit ships with this repo (it is no longer
> gitignored). Personal/runtime state under `.claude/` (`.env`,
> `settings.local.json`, `wiki-pages/`, `worktrees/`, `baselines/`) stays
> gitignored — see `.gitignore`.

---

## Navigation Rule (all modes)

Before any file lookup, grep, or glob, navigate from the structured entry points rather than exploring blindly:

- **For a sysadmin request** → invoke the matching skill in `.claude/skills/` (see **Sysadmin Skills** below). Read that skill's `SKILL.md` first.
- **For host/container/IP lookup** → `utils/cttb-ct.sh list`.
- **For Ansible role/subsystem navigation** → `PROJECT.md` is the operator's infra reference (network architecture, role subsystems, deployment model). It ships with the repo; treat it as the deep-infra map.

---

## Project Files

| Path | Purpose | Ships? |
|------|---------|--------|
| `CLAUDE.md` | Project-specific rules (this file). | yes |
| `PROJECT.md` | Infra reference: network architecture, role subsystems, deployment model. | yes (secrets redacted) |
| `.claude/skills/` | The sysadmin skill catalog (`/sysadmin`, `/ldap`, `/wiki-author`, …). | yes |
| `utils/` | Sysadmin toolkit CLIs: `wiki`, `ldap`, `cttb-ct.sh`, `vault-pass`, `load-cttb-key`, plus the Ansible wrappers (`pb`, `ar`, `reboot`, …). | yes |
| `utils/sysadmintk/` | Shared Python libraries the CLIs import: `cttb_api.py`, `wiki_lib.py`, `ldap_lib.py`, `ansible_env.py`, and the `idstore_*` credential backends. | yes |
| `.claude/sysadmin/` | Compatibility forwarders to `utils/` for the old tool paths. Do not add new tools here. | yes |
| `.claude/settings.json` | Shared Claude Code settings: context-mode plugin + the think-in-code deny hook. | yes |
| `.claude/hooks/`, `.claude/rules/` | Vendored enforcement hook + its rule doc. | yes |
| `.claude/.env.example` | Credential env-var template (commit the template, not the values). | yes |
| `.claude/wiki-pages/` | Wiki page drafts/exports (working copies). **gitignored** — never pushed. | no |
| `.claude/.env` | Real credential values. **gitignored** — never committed. | no |
| `.claude/settings.local.json` | Per-sysadmin local overrides. **gitignored**. | no |
| `WORKPLAN.md` | Session workplan. **gitignored**. | no |

---

## Sysadmin Skills

Invoke with `/<name>`. Each has a `SKILL.md` with the full workflow; the one-liners here are for routing.

| Skill | Use case | Trigger |
|-------|----------|---------|
| `/sysadmin` | Router. Classifies an open-ended ops request to exactly one unit skill below. | `/sysadmin <request>`, or ambiguous ops phrasings ("add a user to a group", "what's the IP of wiki-2404"). |
| `/ldap` | Query and modify the CTTB OpenLDAP directory (`ldap.cttb`): users, groups, posixAccount attrs, password resets, new accounts, arbitrary LDIF. Writes are dry-run until `--risks-confirmed`. | Any LDAP question — read or write. |
| `/wiki-author` | Author/edit/delete/style pages on `wiki.cttb` (MediaWiki 1.43): Mbox/Ambox templates, `MediaWiki:` system messages, Lockdown protection, post-edit cache purges. Sets the authorial voice (connected textbook prose). | Drafting, editing, or styling wiki pages. |
| `/cttb-host` | Reach a CTTB host or container over the right SSH chain; shell/exec/push/pull. | "shell into the LDAP container", "what's the IP of wiki-2404", file transfer to a box. |
| `/cttb-vault` | Ansible-vault operations; the password is supplied by `ansible.cfg`. | edit/view/encrypt/decrypt/rekey vault files. |
| `/github-issues` | File actionable items against `moonexpr/cttb-ansible` with the canonical status labels. | "file a bug for this", "track this task", `/document <thing>` for defects. |
| `/document` | Router for recording work: durable reference knowledge → `/wiki-author`; actionable defect/task → `/github-issues`. | "document this", "write this up", "where should this go". |
| `/release-notes` | Cut a release: scope the diff since the previous tag, write `.claude/release-notes/<tag>.md`, annotated-tag, push, publish the GitHub Release, optionally draft the announcement. | "cut a release", "tag a release", `/release-notes <tag>`, a merge completing a milestone. |
| `/cttb-deploy` | Single-host, tag-scoped Ansible deploy via `sudhanix26-rollout-stage2.yml` with paranoid flags pre-set. **Agent-only.** | A skill/routine needs to deploy a subset of role tasks to one named host. |
| `/cttb-pxe-wait` | Wait out a PXE reinstall and verify the host came back. | After kicking a PXE reinstall, polling for completion. |
| `/register-device` | Move one device off the `block13` quarantine pool into a working DHCP pool on `lxc-dnsmasq`. | "register a device", "get this device online", `/register-device <MAC> [category]`. |
| `/vajra-build` | End-to-end vajra `.deb` build + publish to `apt.cttb` (reprepro). Requires `VAJRA_SRC`. | "build and publish the vajra .deb", a vajra commit ready to ship. |
| `/cttb-pkg-publish` | Generalized cargo-deb publish (design captured; `/vajra-build` is the active consumer). | A vajra-shaped publish need for a non-vajra package. |

---

## Sysadmin Tools (`utils/`)

The toolkit the skills above wrap. All credential-bearing tools resolve secrets through the platform credential store — Keychain, Windows Credential Manager, Linux Secret Service, or the 0600 file store (see **Credentials**); no secret is hardcoded.

The CLIs live in `utils/`; the Python they share lives in `utils/sysadmintk/` and is imported by same-directory name (`from cttb_api import …`), so each entrypoint puts that one directory on `sys.path`. Old `.claude/sysadmin/<tool>` paths still work via forwarding shims, but `utils/<tool>` is canonical — the toolkit is not Claude-specific and should be reachable without knowing what Claude is.

### Ansible environment (`setup-env`, `ansible-env`, `pb`)

```bash
source utils/setup-env                      # load ANSIBLE_* into the current shell
utils/ansible-env                           # show what would be resolved, change nothing
utils/pb <playbook> [ansible-playbook OPTS] # run plays/<playbook>.yml
```

`utils/ansible-env` resolves the repo root with `git rev-parse --show-toplevel` (falling back to the working directory) and derives every path from it. `setup-env` is a thin shim that `eval`s its `--export` output — it must be **sourced**, since a child process cannot export into its parent.

**Inventory precedence**, highest first: `-i` on the command line → `$ANSIBLE_INVENTORY` → `inventory/hosts`. `pb` deliberately does *not* pass `-i`; it sets `ANSIBLE_INVENTORY` in the child environment, because a second `-i` is additive in Ansible (it merges sources rather than replacing them) and would make the wrapper's choice impossible to override. To target the flat upgrade-target list, which is the one carrying MAC addresses:

```bash
ANSIBLE_INVENTORY=inventory/sudhanix26_hosts.ini utils/pb util-wakeonlan -l drbu_cs_lab
```

`ANSIBLE_HOSTS` is exported as an alias of `ANSIBLE_INVENTORY` because `utils/ar`, `utils/reboot`, and `utils/shutdown` still pass it as `-i`.

### Hosts and containers (`cttb-ct.sh`)

```bash
utils/cttb-ct.sh list                       # registered host/container aliases
utils/cttb-ct.sh shell <alias>              # interactive shell (wiki, ldap, srv-vm, pxe, ...)
utils/cttb-ct.sh exec  <alias> <cmd...>     # one-shot command
utils/cttb-ct.sh push  <alias> <local> <remote>
utils/cttb-ct.sh pull  <alias> <remote> <local>
```

Edit the `ssh_chain()` host tables at the top of the script to add hosts. SSH ProxyJump for `*.cttb` is configured in `~/.ssh/config`.

### Ansible vault

```bash
ansible-vault edit group_vars/all/vault.yml    # no password flag needed
utils/vault-pass                               # raw helper (prints the password)
```

`ansible.cfg` sets `vault_password_file = utils/vault-pass`, so every `ansible-vault` and `ansible-playbook` invocation picks the password up automatically — `--vault-password-file` is never needed. The path is relative to `ansible.cfg`, so **run from the repository root**.

`vault-pass` resolves `CTTB_VAULT_PASS` through the shared Python credential layer (`cttb_api`), which auto-detects the platform: macOS Keychain, Windows Credential Manager, Linux Secret Service (`secret-tool`), and a `~/.config/cttb/secrets/<SERVICE>` file store at mode 0600 as the headless fallback. It fails closed — exit 2, nothing on stdout — rather than handing `ansible-vault` an empty password. There is no `$CTTB_VAULT_PASS` environment-variable path.

Known issue: `vars/jc_passwds.enc.yml` does not decrypt with the current password (encrypted with a different, now-unknown one). Only `plays/util-hardware-survey-dbg.yml` loads it.

### Wiki API (`wiki`)

Unified Python CLI for `wiki.cttb` (MediaWiki 1.43.x). Auth is handled automatically per command — no separate login step.
**Credentials** in the platform credential store (`WIKI_CTTB_BOT_USER`, `WIKI_CTTB_BOT_PASSWD`); env vars override.
**Library**: `utils/sysadmintk/wiki_lib.py` (WikiContext → WikiSession → API functions). Shared base: `utils/sysadmintk/cttb_api.py`.

```bash
utils/wiki probe "Title-A" "Title-B"                  # check existence (anon; --login for IT namespace)
utils/wiki get "Page Title"                            # pull wikitext into .claude/wiki-pages/
utils/wiki get "Page Title" -                          # print to stdout
utils/wiki edit "Page Title" .claude/wiki-pages/Page_Title.txt "msg"
utils/wiki purge "Page Title" ["Other Title" ...]      # purge cache via the API (run after every edit)
utils/wiki purge --force "Template:Foo"                # + forcelinkupdate (after Template edits)
utils/wiki history "Page Title" -n 5 --login           # recent revisions (timestamp, user, summary)
utils/wiki delete "Page Title" "deletion reason"       # sysop right
utils/wiki audit-drafts                                # audit .claude/wiki-pages/ vs live wiki
utils/wiki upload .claude/wiki-pages/image.svg "description"
utils/wiki sitenotice .claude/wiki-pages/wiki-sitenotice.txt
utils/wiki push-notice                                 # push wiki-sitenotice.txt + wiki-commonjs.txt
utils/wiki maint <subcommand> [args...]                # run MW maintenance/run.php on wiki via ssh
```

- API: `http://wiki.cttb/w/api.php` (container wiki-2404 at 10.11.1.34)
- **All wiki.cttb API access goes through this CLI — never hand-roll `curl`/`wget` against the API** (the think-in-code hook denies it, in Bash and in the `ctx_*` sandbox alike). A missing capability means extending the CLI (`wiki_lib.py`), not inlining HTTP.
- Bot edits: `http://wiki.cttb/wiki/Special:Contributions/<redacted>` (the bot user named in `WIKI_CTTB_BOT_USER`)
- Sitenotice dismiss: increment the key in `MediaWiki:Common.js` to re-show after dismiss
- For deeper wiki authoring guidance use the `/wiki-author` skill.

### LDAP (`ldap`)

Unified Python CLI for the CTTB directory. Defaults: `ldap://ldap.cttb`, `dc=cttb`, authenticated simple bind, StartTLS (cert validation off). Run locally — no jump host needed.
**Credentials** in the platform credential store (`CTTB_LDAP_USERNAME`, `CTTB_LDAP_PASSWD`); env vars override. Username may be a bare uid or a full DN.
**Library**: `utils/sysadmintk/ldap_lib.py` (LdapContext + API functions). Shared base: `utils/sysadmintk/cttb_api.py`.
**All writes are dry-run by default** — pass `--risks-confirmed` to mutate.

```bash
utils/ldap search '(uid=<redacted>)' cn mail          # raw LDIF to stdout
utils/ldap search -b ou=Groups,dc=cttb '(cn=it)' memberUid gidNumber
utils/ldap search --anon '(uid=<redacted>)' cn          # anonymous bind
utils/ldap group it                                    # one group's members (primary + secondary)
utils/ldap group --all                                 # every posixGroup
utils/ldap apply foo.ldif                              # dry-run LDIF (server validates, no writes)
utils/ldap apply foo.ldif --risks-confirmed            # apply
utils/ldap add-to-group <uid> <group> [--risks-confirmed]
utils/ldap passwd <uid> [--risks-confirmed]            # password reset (RFC 3062)
utils/ldap add-user --uid jdoe --cn "Jane Doe" --sn Doe \
    --uid-number 2099 --gid-number 2099 [--risks-confirmed]
```

- Group base: `ou=Groups,dc=cttb` (plural)
- People base: `ou=People,dc=cttb`
- `posixGroup` membership = `memberUid` on the group **plus** any user whose primary `gidNumber` matches — `ldap group` resolves both.
- For deeper LDAP query / mutation guidance use the `/ldap` skill.

---

## context-mode (required)

`context-mode` is installed as a **project plugin** (`.claude/settings.json` → marketplace `mksglu/context-mode`). It provides the `ctx_*` tools (`ctx_batch_execute`, `ctx_execute`, `ctx_execute_file`, `ctx_search`, `ctx_fetch_and_index`) that run commands/code in a sandbox, index the full output, and return only a derived summary — keeping raw bytes out of the conversation.

A PreToolUse hook (`.claude/hooks/pre-tool-think-in-code.py`) **denies** oversized raw `Bash`/`Read` and unbounded `grep -r`/`find`/bare `rg`, redirecting you to the `ctx_*` tools. This is mandatory for every sysadmin working in this repo.

- **Gather** (recursive search, multi-command shell) → `ctx_batch_execute`
- **Process/derive** (filter, count, aggregate, parse a file) → `ctx_execute` / `ctx_execute_file`
- **Query an indexed corpus** → `ctx_search`
- **Fetch a web page for analysis** → `ctx_fetch_and_index` (not `WebFetch`)

Escape hatches (use sparingly, with a stated reason): per-command `THINK_IN_CODE_DISABLE=1 <cmd>`; warn-only `export THINK_IN_CODE_DENY_DISABLE=1`; session `export THINK_IN_CODE_DISABLE=1`. Full principle: `.claude/rules/think-in-code.md`.

---

## Credentials

No secret is committed. The toolkit reads credentials from the platform credential store, auto-detected by `cttb_api._detect_idstore()`:

| Platform | Store | Add a credential |
|---|---|---|
| macOS | Keychain | `security add-generic-password -s <SERVICE> -a "$USER" -w` |
| Windows | Credential Manager | `cmdkey /generic:CTTB/<SERVICE> /user:. /pass:<value>` |
| Linux / WSL | Secret Service (libsecret) | `secret-tool store --label=<SERVICE> service <SERVICE>` |
| any, headless | file store, mode 0600 | `printf '%s' '<value>' > ~/.config/cttb/secrets/<SERVICE>` |

The file store is chained last on every platform, so headless servers, cron, and bare WSL shells (no D-Bus keyring) still resolve credentials.

- **Template**: `.claude/.env.example` — env vars are an accepted fallback for the wiki/LDAP credentials only, and are read *before* the store by `credential_or_env()`.
- **`CTTB_VAULT_PASS` has no env-var path.** It resolves only through the store (or the 0600 file), via `utils/vault-pass`.
- **Services**: `CTTB_VAULT_PASS`, `WIKI_CTTB_BOT_USER`, `WIKI_CTTB_BOT_PASSWD`, `CTTB_LDAP_USERNAME`, `CTTB_LDAP_PASSWD`. (`VAJRA_SRC` is a path, not a secret — env only.)

Rule: never hardcode a token, password, or personal account name in a committed file. Use the `<redacted>` placeholder in docs/examples and read live values from the store/env at runtime.

---

## Wiki Page Drafts (`.claude/wiki-pages/`)

**Always save wiki page drafts and exports here**, never in `/tmp/`. Filename convention: page title with spaces and `:` replaced by `_` (e.g. `IT:Sudhanix` → `IT_Sudhanix.txt`, `Main Page` → `Main_Page.txt`).

The directory is gitignored so drafts are never accidentally pushed. They persist across sessions for iterative editing and side-by-side diffs against the live wiki.

---

## Operational Conduct

> These rules are embedded from the operator's global framework so this repo is
> self-contained. They apply in every session that works in this repo.

### Judgment calls

- **Ambiguous scope:** take the conservative interpretation and note the assumption.
- **Decisions that could go either way:** flag them. Do not silently expand scope.
- **Technical calls are yours to make and report.** Resolve engineering questions; escalate only when the answer requires product or priority input.
- **Research before acting.** When a request references something unfamiliar (a tool, library, threat, concept), search the web or ask for clarification *before* acting. Impulsiveness causes system harm; on this repo that means real outages on a live network.

### Scope discipline

A new ask is **creep** when it is not required to satisfy the current goal's validators. "Adjacent" ≠ in-scope. "Easy to also do" ≠ in-scope. When creep appears:

1. Stop the current edit/tool stream.
2. Name the new ask in one line and restate the active goal.
3. Use `AskUserQuestion` with three options (default **Defer**):
   - **Defer** — log the request, finish the current goal first.
   - **Expand scope** — the operator explicitly enlarges the goal; update the validator set before continuing.
   - **Pivot** — abandon the current goal for the new ask.

**On Defer** — file the request as a GitHub issue via the `/github-issues` skill (or `/document`, which routes there for actionable items), then finish the current goal. Do **not** "just quickly" do the deferred ask after logging it — the discipline is the value.

### Asking questions

Prefer `AskUserQuestion` over guessing. A 10-second clarification beats a 10-minute wrong-direction implementation. Ask when:

- Scope, target, or success criteria are ambiguous and the wrong interpretation would waste meaningful work.
- A decision is irreversible or affects shared state (deletes, force-pushes, schema changes, external messages, production deploys).
- Multiple reasonable approaches exist with materially different trade-offs.
- You would otherwise make an assumption you'd defend in a PR review — surface it instead.

Skip the question for routine, locally-reversible actions (a file edit, a small refactor, running tests), or when the answer is obviously inferable from `CLAUDE.md`, recent conversation, or git state. When in doubt, ask.

### Script and artifact persistence

Do not write scripts, helpers, or one-off output artifacts to `/tmp` or the Desktop. `/tmp` is wiped on reboot — and reboot/PXE tests are common here. Persistence targets, in order:

1. A **skill's helper** script → the skill's own folder (`<skill-dir>/scripts/`), listed in its `## Resources` section.
2. A **project-scoped helper** → a durable repo location (`scripts/`, `tools/`, `utils/`).
3. A **named deliverable** (scrape, report, transcript) → `.claude/artifacts/` (create the subdir if the parent `.claude/` exists), or a clearly-named path under `out/`/`research/`. Mention the location in your turn summary.

A script's existence should outlive the turn that needed it. The next agent should find it, not regenerate it from scratch.

### Git commit signing

On machines where the signing key has a passphrase and agent sessions have no TTY (the operator's Mac, with the `gpg-loopback` wrapper in `~/.local/bin`), a bare `git commit` hangs. Use:

```bash
git -c gpg.program=gpg-loopback commit -m "..."
```

For throwaway/fixup commits where signing is intentionally undesired: `git commit --no-gpg-sign -m "..."` (say why in the message). On sysadmin machines **without** the wrapper, use the inline form `git -c gpg.program='gpg --batch --pinentry-mode loopback --passphrase <P>' commit` if your key needs loopback, or a plain `git commit` if your gpg agent can prompt normally.

### No session-link leakage

Never write a Claude Code session permalink (`https://claude.ai/code/session_<id>`) into a commit message, PR body, PR/issue comment, or any durable VCS record. It cannot be un-leaked once pushed. If a template or footer would append it, strip it before the `git commit` / `gh` call.

### Think in code

Default: program the analysis, do not compute it by eye. For "count X", "find all Y", or "aggregate Z", write code that prints the answer; route recursive `grep`/`find` and large output through the `ctx_*` tools (see **context-mode** above). Full principle and escape hatches: `.claude/rules/think-in-code.md`.

### Repo labels

When filing an issue or labeling a PR, carry exactly one status rung on the canonical ladder: **`Unscheduled` → `Draft` → `Candidate` → `Release`**. If a canonical rung is missing on the repo, add it (`gh label create <name> --color <hex>`) rather than inventing a substitute or omitting it.