`plays/util-screenshot.yml` reports a screenshot path that does not exist. The file is fetched correctly, but under a different name than the one printed in the final task, so anyone following the play's own output gets a "No such file or directory".

## Repro

```bash
utils/pb util-screenshot --limit <hostname> --become-password-file utils/vault-pass
ls -la logs/screenshots/
```

## Expected

The path printed by the `report screenshot location` task is the path the file was written to.

## Actual

Observed 2026-08-06 against `drbu-sw-cslab-w-pc3.cttb`:

```
TASK [report screenshot location]
  "msg": "Screenshot saved to .../logs/screenshots/drbu-sw-cslab-w-pc3.cttb-20260806-175935.png"

$ ls logs/screenshots/
drbu-sw-cslab-w-pc3.cttb-20260806-175932.png     # <-- 3 seconds earlier
```

## Root cause

`plays/util-screenshot.yml:23`:

```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
```

Play `vars` are lazily-evaluated Jinja templates, not constants. `timestamp` is referenced twice — once in the `fetch` task's `dest`, once in the `debug` msg — and each reference re-runs `lookup('pipe', ...)`, executing `date` again. Any wall-clock seconds that elapse between the two tasks produce two different names. The gap is usually small enough to look like a cosmetic oddity and large enough to break a copy-paste of the reported path.

The same latent bug would corrupt any future task that references `timestamp`, and it makes the play non-idempotent in its naming.

## Repo locations

- `plays/util-screenshot.yml:23` — the lazily-evaluated `timestamp` var
- `plays/util-screenshot.yml:64` — `fetch` dest, first evaluation
- `plays/util-screenshot.yml:75-77` — `debug` msg, second evaluation

## Acceptance criteria

- [ ] `timestamp` is evaluated exactly once per play run
- [ ] The path printed by `report screenshot location` is byte-identical to the file actually written
- [ ] Two consecutive runs produce two distinctly-named files (no clobber)

## Where to look first

Freeze the value with `set_fact` before the fetch, since `set_fact` evaluates eagerly and caches:

```yaml
tasks:
  - name: freeze timestamp for this run
    set_fact:
      timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
    run_once: true
```

then drop `timestamp` from `vars`. Alternatively use `ansible_date_time.iso8601_basic_short`, though that requires `gather_facts: true`, which the play deliberately disables.

## Context

Hit while smoke-testing the remote-screenshot path against `drbu-sw-cslab-w-pc3.cttb` on 2026-08-06. The screenshot itself worked correctly — this is purely the reported-vs-actual filename mismatch. Low severity, but it wastes a minute every time someone trusts the play's output.
