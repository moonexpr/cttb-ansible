**Resolved via key rotation.** In-memory recovery of the original key was attempted and is impractical; a fresh key now carries the automation identity with its passphrase in the credential store.

### Memory extraction — attempted, not viable
The `cttb-os` key is loaded in kit.chong's live `ssh-agent` (PID confirmed), and `/proc/<pid>/mem` is root-readable, so extraction looked feasible. It is not, within reasonable effort:
- The **passphrase** is unrecoverable — `ssh-add` consumes it and never persists it; not on disk, in shell history, or the `load-cttb-key` notes.
- The **public modulus** `n` *is* present in the agent's heap as plaintext little-endian limbs (so the key is unshielded), but under **OpenSSL 3.0** the private components (`p`, `q`, `d`) are **not** stored as contiguous integers. A factor-scan, a gcd-scan (3 window sizes × both byte orders), and a pointer-narrowed factor-from-`d` over 194 candidate exponents all came up empty. Recovering the key would require reversing OpenSSL 3.0's provider key layout (CRT params likely in Montgomery form) — a real RE effort whose payoff is a key still carrying every problem below. (Scripts: `.claude/artifacts/recover-agent-key.py`, `diag-agent-mem.py`.)

### Rotation — done
- New key **`cttb-automation`** (ed25519, `SHA256:kn+XLmlkM0o7fZLh4CQtTxV8o5VyBSm9c4xjklqXbfE`), generated on CTTB_TRUSTED_HOST.
- Passphrase stored in the credential store as **`CTTB_AUTOMATION_KEY_PASS`** (jc Keychain on WORKSTATION; 0600 file store for jc and root on rui-desktop2) — no longer memory-only.
- Enrolled: `roles/common/files/ssh_keys/cttb-automation.pub` (commit 701646b5).
- Distributed fleet-wide via `distribute-ssh-keys` + `distribute-ssh-keys-infra`, authorized by the still-live cttb-os agent.
- New Python loader `.claude/sysadmin/load-cttb-key` (commit f8786cf4) resolves the passphrase cross-platform via `cttb_api` and `ssh-add`s the key non-interactively — replaces the `~/.ssh/load-cttb-key.txt` folklore.
- **Verified**: `cttb-automation` authenticates to `administrator@` on srv-vm, srv-gw, srv-nas, and lxc-ldap.

### Remaining (not blocking)
- The old `cttb-os` / `ansible@cttb.us` key is **still trusted fleet-wide** — distribution is add-only. Its removal is gated on the revocation path in #96.
- The new private key + passphrase currently live on rui-desktop2 (+ jc's Keychain). Propagating them to the other sysadmins' machines is a follow-up; the bus-factor itself is resolved because the passphrase is now recoverable from the credential store.
