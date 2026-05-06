# ldap-schema-sudhanix

Sudhanix-specific schema additions for slapd on `ldap-srv.cttb`.

## What it installs

| Item | OID | Purpose |
|---|---|---|
| `sudhanixWelcomeDismissed` (attributeType) | `1.3.6.1.4.1.99999.1.1.1` | Boolean, single-value. TRUE means the user clicked "Don't show me this anymore" on the Sudhanix welcome panel. |
| `sudhanixUser` (auxiliary objectClass) | `1.3.6.1.4.1.99999.1.2.1` | MAY contain `sudhanixWelcomeDismissed`. Added to a user entry on first dismissal. |
| ACL on `olcDatabase={1}mdb,cn=config` | — | `to attrs=sudhanixWelcomeDismissed by self write by * read` — each user can flip their own flag, everyone can read. |

The role is idempotent: skips schema add if `cn=sudhanix,cn=schema,cn=config` already exists; skips ACL add if `olcAccess` already mentions the attribute.

## Apply

Targets the `ldap_servers` group (the host running slapd):

```bash
ansible-playbook -l ldap-srv playbooks/ldap-server.yml --tags ldap_schema
```

## Validate (`validate.sh`)

Self-contained diagnostic script — no Ansible required. Connects to `ldap.cttb:389` over StartTLS.

```bash
./validate.sh                  # summary: schema check, ACL hint, dismissed-user count + 5 most recent
./validate.sh --user <uid>     # per-user state for one student
./validate.sh --watch          # live monitor; new dismissals appear within 2s
./validate.sh --reset <uid>    # clear flag + sudhanixUser class on UID (prompts for that user's password)
```

### Per-user state classifications

| Output | Meaning |
|---|---|
| `→ DISMISSED` | `sudhanixUser` class present and `sudhanixWelcomeDismissed: TRUE` — happy path |
| `→ has sudhanixUser class but flag not TRUE — partial / stale state` | Interrupted write or manual edit; investigate |
| `→ not dismissed (clean state)` | Never dismissed — fresh student |

### Environment overrides

```bash
CTTB_LDAP_HOST=ldap-srv.cttb ./validate.sh   # use cert CN if you fix the SAN later
CTTB_LDAP_BASE=dc=cttb ./validate.sh
```

### TLS note

The script sets `LDAPTLS_REQCERT=never` because the server cert's CN is `ldap-srv.cttb` while DNS lookups use `ldap.cttb`. Fine for diagnostics; production clients should use `ldap-srv.cttb` directly or the cert should be reissued with a SAN covering both names.

### Suggested test loop

1. Pick a test student account.
2. `./validate.sh --user <uid>` — confirm clean state.
3. `./validate.sh --watch` in one terminal.
4. On a Sudhanix lab desktop, log in as the student → click "Don't show me this anymore".
5. Watcher should flash with the new entry within 2s.
6. `./validate.sh --reset <uid>` — restore clean state for the next test.

## Failure modes worth knowing

| Symptom | Likely cause |
|---|---|
| `validate.sh` reports schema missing | `ldap-schema-sudhanix` role never ran, or ran on the wrong host |
| Dismissal silent — count stays 0 | Welcome app can't bind as the user. Check `/run/sudhanix-tokens/<uid>` exists right after graphical login (PAM `pam_exec` cache hook). |
| `ldapmodify rc=50: Insufficient access` in welcome app log | ACL not applied. Run `--tags ldap_schema` again, then check `olcAccess` on `olcDatabase={1}mdb,cn=config`. |
| `partial / stale state` for a user | Likely a previous failed dismissal left the class behind. `--reset <uid>` to clean up. |

See `roles/sudhanix-core/tasks/sudhanix-welcome.yml` for the client-side deploy that consumes this schema.
