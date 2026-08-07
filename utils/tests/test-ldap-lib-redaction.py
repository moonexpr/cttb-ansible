#!/usr/bin/env python3
"""Regression checks for the ldap_lib credential leak.

subprocess.CalledProcessError renders the full argv in its __str__, and
ldap_lib puts the bind password there as `-w <password>` (and, in
reset_password, the new password as `-s <password>`). Any failing LDAP call
therefore printed both secrets into tracebacks, logs and error reports.

These checks fail loudly if that regresses. They need no LDAP server: the leak
was in how a failure was raised, not in what the directory returned.

Usage:
    utils/tests/test-ldap-lib-redaction.py
"""
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LIB = REPO_ROOT / "utils" / "sysadmintk"
# Same import shape the CLIs use: sysadmintk modules import each other by bare
# name, so the directory goes on sys.path rather than being loaded by file path
# (importlib with an unregistered module name breaks @dataclass resolution).
sys.path.insert(0, str(LIB))

import ldap_lib  # noqa: E402

SECRET = "hunter2-bind-password"
NEW_PW = "hunter3-new-password"
FAILURES = []


def check(name, condition, detail=""):
    print(f"  [{'PASS' if condition else 'FAIL'}] {name}"
          + (f" — {detail}" if detail and not condition else ""))
    if not condition:
        FAILURES.append(name)


def test_run_redacts():
    print("R1 — _run() never surfaces the argv")
    # `false` ignores its arguments and exits 1 — the same shape as a bind
    # failure, with the secret sitting in argv exactly where bind_args puts it.
    argv = ["false", "-x", "-D", "cn=admin,dc=cttb", "-w", SECRET,
            "-s", NEW_PW, "uid=someone,ou=People,dc=cttb"]
    try:
        ldap_lib._run(argv)
        check("a non-zero exit raises", False, "it returned normally")
        return
    except ldap_lib.LdapCommandError as e:
        text = f"{e} {e!r} {getattr(e, 'stderr', '')}"
        check("a non-zero exit raises LdapCommandError", True)
        check("the bind password is absent from the exception",
              SECRET not in text)
        check("the new password is absent from the exception",
              NEW_PW not in text)
        check("the bind DN is absent (argv not rendered)",
              "cn=admin,dc=cttb" not in text)
        check("the return code is still reported", "1" in str(e))
        check("the tool is still named", "false" in str(e))
    except subprocess.CalledProcessError as e:
        check("CalledProcessError no longer escapes", False,
              "it did — the argv leak is back")


def test_stderr_preserved():
    print("R2 — diagnostics still reach the caller")
    try:
        ldap_lib._run(["sh", "-c", "echo 'ldap_bind: Invalid credentials (49)' >&2; exit 49",
                       "-w", SECRET])
        check("non-zero exit raises", False)
    except ldap_lib.LdapCommandError as e:
        check("stderr is surfaced so failures stay diagnosable",
              "Invalid credentials (49)" in str(e), str(e))
        check("and still carries no secret", SECRET not in str(e))
        check("returncode attribute is set", e.returncode == 49)


def test_no_check_true():
    print("R3 — no call site re-introduces check=True")
    src = (LIB / "ldap_lib.py").read_text()
    # Strip docstrings/comments so the prose in _run's own docstring, which
    # names check=True to explain the hazard, is not counted as a call site.
    code = "\n".join(l for l in src.splitlines()
                     if not l.lstrip().startswith("#"))
    import ast
    tree = ast.parse(src)
    offenders = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            fn = node.func
            name = getattr(fn, "attr", getattr(fn, "id", ""))
            if name == "run" and getattr(getattr(fn, "value", None), "id", "") == "subprocess":
                for kw in node.keywords:
                    if kw.arg == "check" and getattr(kw.value, "value", False) is True:
                        offenders.append(node.lineno)
    check("no subprocess.run(check=True) anywhere in ldap_lib",
          not offenders, f"lines {offenders}")

    calls = [n.lineno for n in ast.walk(tree)
             if isinstance(n, ast.Call)
             and getattr(getattr(n.func, "value", None), "id", "") == "subprocess"
             and getattr(n.func, "attr", "") == "run"]
    check("subprocess.run is called in exactly one place (_run)",
          len(calls) == 1, f"{len(calls)} call sites at {calls}")


def main():
    test_run_redacts()
    test_stderr_preserved()
    test_no_check_true()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): " + ", ".join(FAILURES))
        sys.exit(1)
    print("Credential redaction holds.")


if __name__ == "__main__":
    main()
