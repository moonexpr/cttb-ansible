"""Provision NFS home directories and disk quotas on the CTTB fileserver.

The annual batch enrollment (see the project CLAUDE.md "Batch" procedure)
creates LDAP accounts (step 4) and then, on the fileserver, a home directory
plus a disk quota for each new account (step 5 -- the old ``./add-folders.sh``).
That second step was never owned by Ansible: the ``nfs-home`` role is client-side
autofs only, and no quota task exists anywhere in the repo. This module is the
durable replacement, exposed as the ``utils/nfs-homes-provision`` CLI.

It runs the provisioning as root on the fileserver over SSH: a generated bash
script is fed to ``sudo -S bash -s`` with the sudo password supplied as the
first stdin line, so the secret never appears in argv, the process list, or
shell history. Idempotent -- a home that already exists is reported and left
untouched, so a partially-completed run can simply be re-run.

Convention (verified against existing drbu-students ``claire.robb`` /
``hasan.friggle``): ``/nethomes/<uid>`` mode 0700, owner ``<uidNumber>:<gid>``
(drbu-students = 2002), quota copied from a prototype user via ``setquota -p``.
"""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass

import ldap_lib as l
from cttb_api import credential_or_env

# ── validation at the seam ────────────────────────────────────────────────────
# Everything interpolated into the remote bash script is checked here, so the
# script builder can trust its inputs (hopeful-implementation: prove invariants
# once, at the boundary, then proceed cleanly).
_SAFE_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]{0,31}$")
_SAFE_PATH = re.compile(r"^/[a-zA-Z0-9/._-]+$")


def _check_name(value: str, what: str) -> str:
    if not isinstance(value, str) or not _SAFE_NAME.match(value):
        raise ValueError(f"unsafe {what}: {value!r} (must match {_SAFE_NAME.pattern})")
    return value


def _check_path(value: str, what: str) -> str:
    if not isinstance(value, str) or not _SAFE_PATH.match(value):
        raise ValueError(f"unsafe {what}: {value!r} (must match {_SAFE_PATH.pattern})")
    return value


# ── cohort selection ──────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Account:
    uid: str
    uid_number: int


def select_cohort(gid_number: int, uid_min: int,
                  uid_max: int | None = None) -> list[Account]:
    """posixAccount entries in a gid whose uidNumber falls in [uid_min, uid_max].

    The directory is the source of truth for uid -> uidNumber, so "the accounts
    I just enrolled" is selected by gid + the new uidNumber band without
    re-listing them. Dedupes by uidNumber and returns the band sorted ascending.
    """
    ctx = l.LdapContext.default()
    flt = f"(&(objectClass=posixAccount)(gidNumber={gid_number}))"
    entries = l.search(ctx, flt, ["uid", "uidNumber"], base=ctx.people_ou)
    by_num: dict[int, Account] = {}
    for e in entries:
        uids = [v.strip() for v in e.get("uid", []) if v.strip()]
        for n in e.get("uidnumber", []):
            if not n.strip().isdigit():
                continue
            num = int(n.strip())
            if num < uid_min or (uid_max is not None and num > uid_max):
                continue
            if uids and num not in by_num:
                by_num[num] = Account(uids[0], num)
    return [by_num[n] for n in sorted(by_num)]


# ── remote scripts ────────────────────────────────────────────────────────────

def build_provision_script(accounts: list[Account], proto: str, fs: str,
                           gid_number: int) -> str:
    """Bash to run as root on the fileserver. One 'uidNumber uid' line per account."""
    _check_name(proto, "prototype user")
    _check_path(fs, "filesystem")
    for a in accounts:
        _check_name(a.uid, "uid")
    cohort = "\n".join(f"{a.uid_number} {a.uid}" for a in accounts)
    return f"""set -u
PROTO={proto}
FS={fs}
GID={gid_number}
ok=0; skip=0; fail=0
while read -r uidn uid; do
  [ -z "${{uidn:-}}" ] && continue
  dir="$FS/$uid"
  if [ -e "$dir" ]; then
    echo "SKIP exists: $uid ($dir) — left untouched"
    skip=$((skip+1)); continue
  fi
  if ! mkdir "$dir" 2>/dev/null; then
    echo "FAIL mkdir: $uid ($uidn)"; fail=$((fail+1)); continue
  fi
  chown "$uidn:$GID" "$dir" || {{ echo "FAIL chown: $uid"; fail=$((fail+1)); continue; }}
  chmod 700 "$dir" || {{ echo "FAIL chmod: $uid ($uidn)"; fail=$((fail+1)); continue; }}
  mode=$(stat -c %a "$dir")
  if [ "$mode" != "700" ]; then
    echo "WARN $uid ($uidn)  home mode=$mode (expected 700) — chmod did not take"; fail=$((fail+1)); continue
  fi
  if setquota -u "$uidn" -p "$PROTO" "$FS" 2>/dev/null; then
    echo "OK $uid ($uidn)  home $mode owner=$uidn:$GID quota=proto:$PROTO"
    ok=$((ok+1))
  else
    echo "WARN $uid — home created, setquota failed"; fail=$((fail+1))
  fi
done <<EOF
{cohort}
EOF
echo "summary: ok=$ok skip=$skip fail=$fail"
"""


def build_verify_script(accounts: list[Account], fs: str) -> str:
    """Read-only: stat each home and report its quota usage/limit. Creates nothing."""
    _check_path(fs, "filesystem")
    for a in accounts:
        _check_name(a.uid, "uid")
    cohort = "\n".join(f"{a.uid_number} {a.uid}" for a in accounts)
    return f"""set -u
FS={fs}
have=0; missing=0; noquota=0
while read -r uidn uid; do
  [ -z "${{uidn:-}}" ] && continue
  dir="$FS/$uid"
  if [ ! -e "$dir" ]; then
    echo "MISSING $uid ($uidn)"; missing=$((missing+1)); continue
  fi
  s=$(stat -c "%a %u:%g" "$dir")
  q=$(quota -s -u "$uidn" 2>/dev/null | awk '/\\/dev\\//{{print $3"/"$4}}')
  if [ -z "$q" ]; then q="(no quota)"; noquota=$((noquota+1)); fi
  echo "HAVE $uid ($uidn)  mode=$s  quota=$q"
  have=$((have+1))
done <<EOF
{cohort}
EOF
echo "summary: have=$have missing=$missing noquota=$noquota"
"""


# ── remote execution ──────────────────────────────────────────────────────────

def sudo_password() -> str:
    """The fileserver's sudo password from the credential store (env override honored)."""
    pw = credential_or_env("CTTB_FS_ADMIN_PASSWD")
    if not pw:
        raise SystemExit(
            "error: this command needs CTTB_FS_ADMIN_PASSWD in the credential store "
            "(env override honored). On macOS:\n"
            '  security add-generic-password -s CTTB_FS_ADMIN_PASSWD -a "$USER" -w\n'
            "On Linux:\n"
            "  secret-tool store --label=CTTB_FS_ADMIN_PASSWD service CTTB_FS_ADMIN_PASSWD\n"
            "Or headless (mode 0600): install -m 600 /dev/null ~/.config/cttb/secrets/CTTB_FS_ADMIN_PASSWD && "
            "printf %%s '...' > ~/.config/cttb/secrets/CTTB_FS_ADMIN_PASSWD"
        )
    return pw


def run_remote(host: str, user: str, script: str, *, dry_run: bool) -> tuple[int, str]:
    """Feed `script` to `sudo -S bash -s` on host over SSH; password leads on stdin.

    Returns (returncode, combined_output). In dry_run the script is not executed
    and (0, "") is returned -- the caller prints the script for review instead.
    """
    if dry_run:
        return 0, ""
    cmd = ["ssh", "-o", "BatchMode=yes", f"{user}@{host}", "sudo -S -p '' bash -s"]
    proc = subprocess.Popen(
        cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True,
    )
    out, _ = proc.communicate(sudo_password() + "\n" + script)
    return proc.returncode, out