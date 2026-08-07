## Repro

```python
from utils.sysadmintk import ldap_lib as l

ctx = l.LdapContext(bind_dn="uid=nonexistent,ou=People,dc=cttb", bind_pw="SECRETVALUE")
try:
    l.search(ctx, "(uid=nobody)", ["uid"])
except Exception as exc:
    print(str(exc))
```

Any non-zero exit from `ldapsearch` / `ldapmodify` / `ldappasswd` raises `subprocess.CalledProcessError`, whose `__str__` renders the full `cmd` argv — and the argv contains the bind password as `-w <password>` (and, for `reset_password`, the new password as `-s <password>`).

## Expected

A failing `search` / `search_raw` / `apply_ldif` / `reset_password` raises an exception whose `str()` (and therefore any traceback, `print(exc)`, log line, or error report carrying it) does **not** contain the bind password or the new password. The error should still name the ldap return code and the tool's stderr so callers can diagnose.

## Actual

```
Command 'ldapsearch -ZZ -LLL -H ldap://ldap.cttb -b dc=cttb -x -D uid=nonexistent,ou=People,dc=cttb -w SECRETVALUE (uid=nobody) uid' returned non-zero exit status N.
```

`SECRETVALUE` is in the exception message verbatim. For `reset_password` the argv additionally carries the new password as `-s <new_password>`, so a failed password reset leaks both the caller's bind password and the user's new password.

## Repo locations

- `utils/sysadmintk/ldap_lib.py:53` — `bind_args()` returns `-w <bind_pw>` as a literal argv element.
- `utils/sysadmintk/ldap_lib.py:107` — `search()` runs `subprocess.run(..., check=True)`.
- `utils/sysadmintk/ldap_lib.py:126` — `search_raw()` runs `subprocess.run(..., check=True)`.
- `utils/sysadmintk/ldap_lib.py:196` — `apply_ldif()` runs `subprocess.run(..., check=True)`; reached transitively by `add_to_group()` and `add_user()`.
- `utils/sysadmintk/ldap_lib.py:284` — `reset_password()` runs `subprocess.run(..., check=True)`; argv carries both `-w <bind_pw>` and `-s <new_password>`.

## Acceptance criteria

- [ ] A failing `search` / `search_raw` / `apply_ldif` / `reset_password` raises an exception whose `str()` does not contain the bind password.
- [ ] A failing `reset_password` exception does not contain the new password.
- [ ] The surfaced error still includes the ldap return code and the tool's stderr (which the ldap tools print without the secret) so callers can diagnose failures.
- [ ] No regression in `utils/ldap`, `utils/ldap-enroll-csv`, or `utils/nfs-homes-provision` — their error reporting still names the failure mode (the `explain()` shim in `ldap-enroll-csv` should remain correct, ideally becoming a thin pass-through once the library redacts).
- [ ] (Optional, defense in depth) The bind password no longer appears in `/proc/<pid>/cmdline` either — e.g. migrate from `-w` to `-y <tmpfile>` (mode 0600, unlinked after exec) or another non-argv channel.

## Workaround

Callers can wrap `ldap_lib` calls and redact the exception themselves, as `utils/ldap-enroll-csv`'s `explain()` already does (`ldap-enroll-csv` ~line 253): catch `subprocess.CalledProcessError` and render only `e.returncode` plus a fixed result-code table, never `str(exc)`. This protects that one tool but not any other caller, and does not protect an uncaught traceback.

## Where to look first

`utils/sysadmintk/ldap_lib.py`. Introduce a `_run(cmd, **kw)` helper that wraps `subprocess.run`, catches `CalledProcessError`, and re-raises `RuntimeError(f"ldap command failed (exit {e.returncode}): {e.stderr.strip()}")` (stderr only, no argv). Replace the four `subprocess.run(..., check=True)` call sites (`search`, `search_raw`, `apply_ldif`, `reset_password`). Keep `capture_output=True` (or `stderr=subprocess.PIPE`) so `e.stderr` is populated for the re-raised message.

## Context

Discovered while building `utils/nfs-homes-provision` (the durable replacement for the lost `./add-folders.sh`, step 5 of the annual cohort enrollment) during the 2026 DRBU cohort enrollment. The new cohort tooling calls `ldap_lib` heavily, and a failed bind there would have leaked the directory rootdn password into any error report. The `explain()` shim was added to `ldap-enroll-csv` as a one-tool workaround, but the underlying leak belongs to the library and affects every caller — hence filing rather than leaving the workaround as the fix.