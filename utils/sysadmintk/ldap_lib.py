"""
CTTB LDAP API — wraps ldapsearch / ldapmodify / ldappasswd.

  LdapContext   config + credentials; extends CttbContext
                .default()  binds as the calling sysadmin
                .admin()    binds as the directory rootdn
  search()      ldapsearch wrapper → list of entry dicts
  group_members() resolve posixGroup members (primary + secondary)
  apply_ldif()  ldapmodify wrapper (dry-run by default)
  add_to_group() generate + apply memberUid LDIF
  add_user()    generate + apply posixAccount LDIF
  reset_password() ldappasswd wrapper (dry-run by default)
"""
from __future__ import annotations

import base64
import os
import subprocess
from dataclasses import dataclass, field
from typing import Optional

from cttb_api import CttbContext, credential_or_env


# ── Credential services ───────────────────────────────────────────────────────

# The calling sysadmin's own account — enough for reads and for the writes the
# slapd ACL grants to `it` members.
USER_SERVICES = ("CTTB_LDAP_USERNAME", "CTTB_LDAP_PASSWD")

# The directory rootdn.  Needed for entry creation under ou=People and for any
# modify the personal bind answers with LDAP result 50 (insufficient access).
ADMIN_SERVICES = ("CTTB_LDAP_ADMIN_USERNAME", "CTTB_LDAP_ADMIN_PASSWD")

_STORE_HINT = (
    "Add them to the platform credential store. On macOS:\n"
    "  security add-generic-password -s {user_svc} -a \"$USER\" -w 'cn=admin,dc=cttb'\n"
    "  security add-generic-password -s {pw_svc} -a \"$USER\" -w\n"
    "On Linux/WSL:  secret-tool store --label={user_svc} service {user_svc}\n"
    "Headless:      printf '%s' '<value>' > ~/.config/cttb/secrets/{user_svc}"
)


# ── Context ───────────────────────────────────────────────────────────────────

@dataclass
class LdapContext(CttbContext):
    host: str = "ldap://ldap.cttb"
    base_dn: str = "dc=cttb"
    people_ou: str = "ou=People,dc=cttb"
    groups_ou: str = "ou=Groups,dc=cttb"
    bind_dn: Optional[str] = None
    bind_pw: Optional[str] = None
    anon: bool = False

    @classmethod
    def default(cls, anon: bool = False, admin: bool = False) -> "LdapContext":
        """Resolve a bind identity from the credential store.

        admin=True binds as the directory rootdn (ADMIN_SERVICES) instead of
        the calling sysadmin (USER_SERVICES).  Either pair may be overridden
        by an environment variable of the same name; credential_or_env()
        checks the environment before the store.
        """
        if anon:
            return cls(anon=True)
        user_svc, pw_svc = ADMIN_SERVICES if admin else USER_SERVICES
        user = credential_or_env(user_svc)
        pw   = credential_or_env(pw_svc)
        if not user or not pw:
            raise RuntimeError(
                f"{user_svc} / {pw_svc} not in env or the credential store.\n"
                + _STORE_HINT.format(user_svc=user_svc, pw_svc=pw_svc)
            )
        dn = user if "=" in user else f"uid={user},{cls.people_ou}"
        return cls(bind_dn=dn, bind_pw=pw)

    @classmethod
    def admin(cls) -> "LdapContext":
        """Bind as the directory rootdn.

        Creating entries under ou=People is admin-only, and some modifies the
        personal bind is refused (LDAP result 50) succeed here.  The DN and
        password come from the credential store, so the secret is never typed
        on a command line or left in shell history.
        """
        return cls.default(admin=True)

    def bind_args(self) -> list[str]:
        if self.anon:
            return ["-x"]
        if not self.bind_dn or not self.bind_pw:
            raise RuntimeError("LDAP credentials not set — call LdapContext.default()")
        return ["-x", "-D", self.bind_dn, "-w", self.bind_pw]

    def _ldap_env(self) -> dict:
        env = os.environ.copy()
        env["LDAPTLS_REQCERT"] = "never"
        return env


# ── LDIF parser ───────────────────────────────────────────────────────────────

def _parse_ldif(text: str) -> list[dict[str, list[str]]]:
    """Parse -LLL ldapsearch output into a list of {attr: [value, ...]} dicts."""
    entries: list[dict[str, list[str]]] = []
    current: dict[str, list[str]] = {}
    for line in text.splitlines():
        if not line.strip():
            if current:
                entries.append(current)
                current = {}
            continue
        if ":: " in line:
            attr, _, b64 = line.partition(":: ")
            value = base64.b64decode(b64).decode("utf-8", errors="replace")
        elif ": " in line:
            attr, _, value = line.partition(": ")
        else:
            continue
        current.setdefault(attr.lower(), []).append(value)
    if current:
        entries.append(current)
    return entries


def _first(entry: dict, attr: str, default: str = "") -> str:
    return (entry.get(attr) or [default])[0]


# ── Search ────────────────────────────────────────────────────────────────────

def search(
    ctx: LdapContext,
    filter_str: str,
    attrs: list[str] = None,
    base: str = None,
) -> list[dict[str, list[str]]]:
    """Run ldapsearch and return parsed entries."""
    cmd = [
        "ldapsearch", "-ZZ", "-LLL",
        "-H", ctx.host,
        "-b", base or ctx.base_dn,
        *ctx.bind_args(),
        filter_str,
        *(attrs or []),
    ]
    r = subprocess.run(cmd, env=ctx._ldap_env(), capture_output=True, text=True, check=True)
    return _parse_ldif(r.stdout)


def search_raw(
    ctx: LdapContext,
    filter_str: str,
    attrs: list[str] = None,
    base: str = None,
) -> str:
    """Run ldapsearch and return raw LDIF output."""
    cmd = [
        "ldapsearch", "-ZZ", "-LLL",
        "-H", ctx.host,
        "-b", base or ctx.base_dn,
        *ctx.bind_args(),
        filter_str,
        *(attrs or []),
    ]
    r = subprocess.run(cmd, env=ctx._ldap_env(), capture_output=True, text=True, check=True)
    return r.stdout


# ── Group membership ──────────────────────────────────────────────────────────

@dataclass
class GroupResult:
    cn: str
    gid: str
    primary: set[str] = field(default_factory=set)
    members: set[str] = field(default_factory=set)

    def all_uids(self) -> set[str]:
        return self.primary | self.members

    def display(self) -> None:
        print(f"=== {self.cn} (gid={self.gid}) ===")
        for uid in sorted(self.primary):
            print(f"  {uid} (primary)")
        for uid in sorted(self.members - self.primary):
            print(f"  {uid} (member)")
        print()


def group_members(ctx: LdapContext, group_cn: str) -> GroupResult:
    entries = search(ctx, f"(cn={group_cn})", ["gidNumber", "memberUid"], base=ctx.groups_ou)
    if not entries:
        raise RuntimeError(f"group '{group_cn}' not found")
    entry = entries[0]
    gid = _first(entry, "gidnumber")
    member_uids = set(entry.get("memberuid", []))

    primary_uids: set[str] = set()
    if gid:
        rows = search(
            ctx,
            f"(&(objectClass=posixAccount)(gidNumber={gid}))",
            ["uid"],
            base=ctx.people_ou,
        )
        primary_uids = {_first(e, "uid") for e in rows if "uid" in e}

    return GroupResult(cn=group_cn, gid=gid, primary=primary_uids, members=member_uids)


def all_groups(ctx: LdapContext) -> list[GroupResult]:
    entries = search(ctx, "(objectClass=posixGroup)", ["cn"], base=ctx.groups_ou)
    cns = sorted(_first(e, "cn") for e in entries if "cn" in e)
    return [group_members(ctx, cn) for cn in cns]


# ── Write operations (dry-run by default) ────────────────────────────────────

def apply_ldif(ctx: LdapContext, ldif_content: str, *, dry_run: bool = True) -> None:
    """Apply an LDIF via ldapmodify.  dry_run=True (default) contacts the server
    in -n mode so syntax errors surface without writing anything."""
    cmd = [
        "ldapmodify", "-ZZ", "-H", ctx.host,
        *ctx.bind_args(),
        *(["-n"] if dry_run else []),
    ]
    print("--- LDIF ---")
    print(ldif_content.rstrip())
    print("-----------")
    print(f"bind:  {ctx.bind_dn}")
    print(f"mode:  {'dry-run (server validates, no writes)' if dry_run else 'APPLYING'}")
    if dry_run:
        print("       re-run with risks_confirmed=True to apply")
    print()
    subprocess.run(
        cmd, env=ctx._ldap_env(),
        input=ldif_content, text=True, check=True,
    )


def add_to_group(ctx: LdapContext, uid: str, group_cn: str, *, dry_run: bool = True) -> None:
    """Add uid as a secondary memberUid of group_cn."""
    # Validate existence
    if not search(ctx, f"(uid={uid})", ["uid"], base=ctx.people_ou):
        raise RuntimeError(f"user uid={uid} not found")
    if not search(ctx, f"(cn={group_cn})", ["cn"], base=ctx.groups_ou):
        raise RuntimeError(f"group cn={group_cn} not found")

    # Idempotency check
    rows = search(ctx, f"(cn={group_cn})", ["memberUid"], base=ctx.groups_ou)
    existing = set(rows[0].get("memberuid", [])) if rows else set()
    if uid in existing:
        print(f"no-op: {uid} already a memberUid of {group_cn}")
        return

    ldif = (
        f"dn: cn={group_cn},{ctx.groups_ou}\n"
        f"changetype: modify\n"
        f"add: memberUid\n"
        f"memberUid: {uid}\n"
    )
    apply_ldif(ctx, ldif, dry_run=dry_run)


def add_user(
    ctx: LdapContext,
    *,
    uid: str,
    cn: str,
    sn: str,
    uid_number: int,
    gid_number: int,
    given_name: str = "",
    mail: str = "",
    home: str = "",
    shell: str = "/bin/bash",
    dry_run: bool = True,
) -> None:
    """Create a posixAccount + inetOrgPerson entry.
    Password is not set here — use reset_password() after creation."""
    if not home:
        home = f"/home/{uid}"
    lines = [
        f"dn: uid={uid},{ctx.people_ou}",
        "objectClass: top",
        "objectClass: inetOrgPerson",
        "objectClass: posixAccount",
        "objectClass: shadowAccount",
        f"uid: {uid}",
        f"cn: {cn}",
        f"sn: {sn}",
        f"uidNumber: {uid_number}",
        f"gidNumber: {gid_number}",
        f"homeDirectory: {home}",
        f"loginShell: {shell}",
    ]
    if given_name:
        lines.append(f"givenName: {given_name}")
    if mail:
        lines.append(f"mail: {mail}")
    apply_ldif(ctx, "\n".join(lines) + "\n", dry_run=dry_run)


def reset_password(
    ctx: LdapContext,
    target_uid: str,
    new_password: str,
    *,
    dry_run: bool = True,
) -> None:
    """Reset a user's password via ldappasswd (RFC 3062).
    dry_run=True shows what would happen without contacting the server."""
    target_dn = f"uid={target_uid},{ctx.people_ou}"
    masked = "*" * len(new_password)
    print("--- ldappasswd ---")
    print(f"bind:    {ctx.bind_dn}")
    print(f"target:  {target_dn}")
    print(f"new pw:  {masked} ({len(new_password)} chars)")
    print(f"mode:    {'dry-run (no request sent)' if dry_run else 'APPLYING'}")
    if dry_run:
        print("         re-run with risks_confirmed=True to apply")
        return
    subprocess.run(
        ["ldappasswd", "-x", "-ZZ", "-H", ctx.host,
         *ctx.bind_args(), "-s", new_password, target_dn],
        env=ctx._ldap_env(), check=True,
    )
    print(f"ok: password changed for {target_uid}")
