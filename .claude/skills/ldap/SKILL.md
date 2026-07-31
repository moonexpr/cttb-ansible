---
name: ldap
description: >
  Query and modify the CTTB OpenLDAP directory (ldap.cttb) using the
  project-local helpers in `utils/`. Triggers on any LDAP
  question — read (look up users, groups, posixAccount attributes;
  verify group membership for Lockdown / sudo / NFS-export decisions;
  audit the tree shape) or write (add/remove a memberUid, reset a
  password, create a new posixAccount, apply an arbitrary LDIF).
  Helpers default to authenticated simple bind over StartTLS using
  Keychain credentials. Write tools are dry-run by default; require
  `--risks-confirmed` to actually mutate the directory.
---

## When to apply

Apply whenever the question concerns CTTB user/group state in LDAP, in
either direction:

- **Read** — "who's in `it`?", "what's <user>'s primary group?", "list
  every posixGroup with members", "does <uid> exist?", "what's the
  gidNumber of `drbu-faculty`?".
- **Write** — "add Frank to drbu-staff", "reset <redacted>'s
  password", "create an LDAP account for the new student", "remove
  the legacy `lab` group", "rename `dvbs-staff` → `dvbs-faculty`".

Do not apply for local UNIX user lookups (those are in `/etc/passwd`
on each host) or for wiki-side group membership (which is its own
MediaWiki user-rights system, separate from LDAP — see `/wiki-author`).

---

## Tools

All scripts live in `utils/`. Read tools talk to the server
unconditionally; write tools default to **dry-run** and require the
`--risks-confirmed` flag to commit.

### Read

| Script | Purpose |
|--------|---------|
| `ldap-query.sh` | Generic `ldapsearch` wrapper. Pick a base DN, pass an LDAP filter, optionally name attributes. Output is raw LDIF. |
| `ldap-group-members.sh` | Resolve a posixGroup to its full member list — both `memberUid` (RFC 2307 secondary members) and users whose primary `gidNumber` matches. Supports `--all` to walk every group. |

### Write (dry-run by default)

| Script | Purpose | What dry-run shows |
|--------|---------|--------------------|
| `ldap-apply.sh <ldif>` | Generic LDIF dispatcher; the foundation of the others | the LDIF + bind DN + `ldapmodify -n` server-side validation result |
| `ldap-group-add.sh <uid> <group>` | Add a user as `memberUid` of a posixGroup; pre-checks existence, no-ops if already a member | the generated LDIF + dry-run |
| `ldap-passwd.sh <uid>` | RFC 3062 password reset (ldappasswd extended op); prompts twice on TTY, reads stdin otherwise | bind DN, target DN, masked password length |
| `ldap-add-user.sh --uid ... --cn ... --sn ... --uid-number ... --gid-number ... [--given-name ...] [--mail ...] [--home ...] [--shell ...]` | Create a posixAccount + inetOrgPerson + shadowAccount; password set separately via `ldap-passwd.sh` | the generated LDIF + dry-run |

Pass `--risks-confirmed` to commit. The dry-run path still contacts the
server (so syntax errors and permission denials surface), but
`ldapmodify -n` skips the actual write.

---

## Defaults

- Host: `ldap://ldap.cttb`
- Base: `dc=cttb`
- Bind: authenticated simple bind. Username/password read in order from
  `CTTB_LDAP_USERNAME` / `CTTB_LDAP_PASSWD` env vars, then from the
  macOS Keychain entries with the same names. Username can be a full
  DN (`cn=admin,dc=cttb`) or a bare uid (`<redacted>`), in which case
  it is expanded to `uid=<redacted>,ou=People,dc=cttb`.
- TLS: StartTLS with cert validation off (internal self-signed CA).

Pass `-D <dn> -w <pass>` to override (read tools); the write tools
re-use the same env / Keychain logic. For multi-step write sessions
where the bind user has elevated rights, set `CTTB_LDAP_USERNAME` and
`CTTB_LDAP_PASSWD` in the environment for the duration.

---

## Tree shape

| Branch | Holds | Notable attributes |
|--------|-------|--------------------|
| `ou=People,dc=cttb` | `posixAccount` user entries | `uid`, `cn`, `mail`, `uidNumber` (range 2001–9999), primary `gidNumber`, `loginShell`, `homeDirectory`, `sshPublicKey` |
| `ou=Groups,dc=cttb` | `posixGroup` entries (note: plural `Groups`) | `cn`, `gidNumber`, `memberUid` (secondary members) |

Membership semantics: a user is "in" a group if either their primary
`gidNumber` equals the group's `gidNumber`, **or** their `uid` appears
in the group's `memberUid` list. `ldap-group-members.sh` merges both;
do not assume `memberUid` alone is authoritative. Adding a user via
`ldap-group-add.sh` only updates `memberUid` — primary group changes
need a different LDIF (see "Write recipes" below).

---

## Read recipes

```bash
# All members of one group
utils/ldap-group-members.sh it

# Every posixGroup with members
utils/ldap-group-members.sh --all

# One user's full record
utils/ldap-query.sh -b ou=People,dc=cttb '(uid=<redacted>)'

# Just specific attributes
utils/ldap-query.sh -b ou=People,dc=cttb '(uid=<redacted>)' cn mail uidNumber gidNumber

# Group → gidNumber + memberUids
utils/ldap-query.sh -b ou=Groups,dc=cttb '(cn=it)' gidNumber memberUid

# Authenticated bind override (e.g. as admin)
utils/ldap-query.sh -D "cn=admin,dc=cttb" -w "$ADMIN_PW" \
    -b ou=People,dc=cttb '(objectClass=posixAccount)' uid uidNumber

# Sanity check: count active accounts
utils/ldap-query.sh -b ou=People,dc=cttb '(objectClass=posixAccount)' uid \
    | grep -c '^uid:'
```

---

## Write recipes

The convenience wrappers cover the three most common mutations. For
anything else, hand-author an LDIF and pipe it through `ldap-apply.sh`.

### Add a user to a group (memberUid)

```bash
# Dry run — shows the LDIF and validates server-side
utils/ldap-group-add.sh frank.liu drbu-staff

# Commit
utils/ldap-group-add.sh frank.liu drbu-staff --risks-confirmed
```

### Remove a user from a group

No dedicated wrapper; use `ldap-apply.sh`:

```bash
cat <<'EOF' | utils/ldap-apply.sh -
dn: cn=drbu-staff,ou=Groups,dc=cttb
changetype: modify
delete: memberUid
memberUid: frank.liu
EOF
# add --risks-confirmed before the - to commit
```

### Reset a password

```bash
# Interactive — prompts twice
utils/ldap-passwd.sh <redacted> --risks-confirmed

# Scripted — read from stdin
echo 'newpass' | utils/ldap-passwd.sh <redacted> --risks-confirmed
```

The bind user must either be the target or hold a write ACL on the
target's `userPassword`. RFC 3062 lets the server hash the password
according to its own pwdPolicy; do not pre-hash.

### Create a new user

```bash
utils/ldap-add-user.sh \
    --uid jdoe --cn "Jane Doe" --sn Doe --given-name Jane \
    --uid-number 2099 --gid-number 2099 \
    --mail jdoe@dharma.org \
    --risks-confirmed

# Then set the password
utils/ldap-passwd.sh jdoe --risks-confirmed
```

`uidNumber` and `gidNumber` are caller-supplied. Pick the next free
uidNumber by querying the directory first; do not auto-increment
without checking.

### Change a user's primary group

```bash
cat <<'EOF' | utils/ldap-apply.sh -
dn: uid=jdoe,ou=People,dc=cttb
changetype: modify
replace: gidNumber
gidNumber: 2003
EOF
```

### Add an SSH key

```bash
cat <<EOF | utils/ldap-apply.sh -
dn: uid=jdoe,ou=People,dc=cttb
changetype: modify
add: sshPublicKey
sshPublicKey: $(cat ~/.ssh/jdoe-laptop.pub)
EOF
```

### Create a new posixGroup

```bash
NEXT_GID=$(utils/ldap-query.sh -b ou=Groups,dc=cttb \
    '(objectClass=posixGroup)' gidNumber \
    | awk '/^gidNumber:/ {print $2}' | sort -n | tail -1)
NEXT_GID=$((NEXT_GID + 1))

cat <<EOF | utils/ldap-apply.sh -
dn: cn=newgroup,ou=Groups,dc=cttb
changetype: add
objectClass: top
objectClass: posixGroup
cn: newgroup
gidNumber: $NEXT_GID
EOF
```

### Rename / DN-move

`ldap-apply.sh` accepts `changetype: modrdn`:

```ldif
dn: cn=oldname,ou=Groups,dc=cttb
changetype: modrdn
newrdn: cn=newname
deleteoldrdn: 1
```

Subtree moves between OUs use `changetype: moddn` with `newsuperior`.

### Bulk LDIF

For anything generated externally (migration scripts, LDIF exported
from a sister directory), pipe it straight through:

```bash
utils/ldap-apply.sh export.ldif --risks-confirmed
```

---

## LDIF authoring tips

- Each entry is separated by a **blank line**. Forgetting the blank
  line concatenates two changes into one and `ldapmodify` rejects the
  whole batch.
- `changetype:` lines: `add` (new entry), `modify` (attribute changes
  on existing entry), `delete` (remove entry), `modrdn` (rename),
  `moddn` (move). Within `modify`, each operation block (`add: attr`,
  `replace: attr`, `delete: attr`) is terminated by a `-` line; this
  is required for multi-attribute modifications, optional for single.
- Attribute values with leading whitespace, `:`, or `<` need base64
  encoding (`attr:: <base64>`) or file-URL inclusion (`attr:< file://`).
- Comments begin with `#`. They survive `ldapmodify` but are not
  written to the directory.
- LDAP attribute names are case-insensitive, but case is preserved on
  display. Match the case of existing entries when in doubt.

---

## Permission model

The default Keychain bind user (the DN of the uid stored in
`CTTB_LDAP_USERNAME` — `<redacted>`) is in `cn=it`. Whether that
grants write rights depends on the server's slapd ACL:

- **`userPassword` self-write** — every user can change their own.
- **`memberUid` writes on `ou=Groups`** — typically restricted to
  admins or to members of the `it` group; check
  `roles/openldap-server/templates/slapd.conf.j2` for the live ACL.
- **Creating new entries under `ou=People`** — admin-only by convention.
- **Schema-touching operations** (`changetype: add` of a new
  `objectClass` entry, modifying `cn=schema,cn=config`) — require
  binding as `cn=admin,dc=cttb`. Override with `-D`/`-w` (read tools)
  or by setting `CTTB_LDAP_USERNAME=cn=admin,dc=cttb` and
  `CTTB_LDAP_PASSWD` before running write tools.

A dry run that succeeds server-side does not guarantee the real write
will succeed — `ldapmodify -n` skips the ACL check on some setups.
Treat a clean dry run as a syntax check, not a permission check.

---

## Gotchas

- The directory is on **lxc-ldap** (Ubuntu 16.04, OpenLDAP 2.4) and
  the on-disk schema predates Sudhanix — `posixAccount` is the
  canonical objectClass, not `inetOrgPerson` exclusively. Filter on
  `(objectClass=posixAccount)` when iterating users; `(objectClass=*)`
  also returns the OUs and won't have `uidNumber`. When *creating*
  users, the `ldap-add-user.sh` wrapper layers `posixAccount`,
  `inetOrgPerson`, and `shadowAccount` so all attributes are accepted.
- TLS cert validation is intentionally off in the wrappers because
  the CTTB internal CA is self-signed and not always shipped to the
  host running the query. If a host is part of the `cttb-ca-client`
  Ansible role, the CA is trusted and you can flip validation on by
  passing `LDAPTLS_REQCERT=demand`.
- `dc=cttb` is the base. There is no `dc=local`, `dc=cttb,dc=org`, or
  similar alias. Old docs that show `cn=admin,dc=cttb,dc=org` are stale.
- The directory does **not** mirror MediaWiki user groups. The wiki's
  `it` group is a MediaWiki-side group managed via `Special:UserRights`
  and the `wiki-add-group-users.yml` playbook; the LDAP `it` group
  governs sudo/UNIX semantics on lab hosts. They overlap by convention,
  not by sync.
- `ldap.cttb` resolves to the same lxc-ldap container that
  `ldap-srv.cttb` does. Either name works; the helpers use `ldap.cttb`.
- Anonymous bind is allowed for read-only queries but the wrappers
  default to authenticated bind so attribute visibility is predictable
  (some attributes — notably `userPassword`, `sshPublicKey` — are ACL'd
  away from anon).
- A successful `ldap-group-add.sh` only updates `memberUid`. Active
  sessions (sudo timestamps, NFS mounts, polkitd state) won't see the
  new membership until the user re-authenticates. After a group add,
  ask whether the change is needed *now* — re-login may be required.
- `ldap-passwd.sh` uses the Password Modify extended op (RFC 3062).
  Some pwdPolicy overlays reject the op for the bind user even when a
  raw `replace: userPassword` would succeed; if reset is rejected, fall
  back to an `ldap-apply.sh` of:

  ```ldif
  dn: uid=<target>,ou=People,dc=cttb
  changetype: modify
  replace: userPassword
  userPassword: <SSHA-hash>
  ```

  with a hash generated via `slappasswd -h '{SSHA}' -s <new>`.

---

## Where to look

| What | Where |
|------|-------|
| Helper scripts | `utils/` (all `ldap-*.sh` files) |
| Server config | container `lxc-ldap` (10.11.1.25), Ansible role `roles/openldap-server/` |
| Live slapd ACL | `roles/openldap-server/templates/slapd.conf.j2` (search for `access to`) |
| Client config | role `roles/ldap-client/` |
| CA trust | role `roles/cttb-ca-client/` (deploys `CTTB-Root-CA.crt`) |
| Tree shape memo | `.claude/projects/.../memory/reference_cttb_ldap_shape.md` |
| Live LDAP via SSH (last resort) | `ssh ldap` — escalate via Keychain/env credentials, never a hardcoded password |
