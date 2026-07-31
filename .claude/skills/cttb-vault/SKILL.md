---
name: cttb-vault
user-invocable: true
argument-hint: "<edit|view|encrypt|decrypt|rekey> <vault file>"
description: >
  Run any `ansible-vault` subcommand against CTTB vault files. `ansible.cfg`
  sets `vault_password_file = utils/vault-pass`, which reads the
  password from the platform credential store, so there is never a password
  prompt, a `--vault-password-file` flag, or a plaintext password on disk.
  Triggers on "edit group_vars/all/vault.yml", "decrypt the vault file", "view
  a vaulted var", "rekey the vault", `/cttb-vault <subcmd> <file>`, or any
  agent step that must read or change an encrypted Ansible value. One job:
  authenticated ansible-vault access. It does not deploy or run plays.
---

## When to apply

Apply whenever an encrypted Ansible value must be read or changed:
inspecting a vaulted variable, editing `group_vars/all/vault.yml`,
encrypting a new secret file, decrypting for a one-off check, or
rekeying. Do not apply for non-vault YAML edits (use `Edit`
directly), for running playbooks, or for the sudo/SSH credentials a
deploy needs at runtime (those resolve from the credential store at play time).

## Procedure

1. **Confirm the target.** Identify the exact vault file path
   (canonical: `group_vars/all/vault.yml`). Vault files are
   ansible-vault-encrypted; editing them with a plain editor corrupts
   them — always go through `ansible-vault`.

2. **Run the subcommand** from the repository root. No password flag is
   needed; `ansible.cfg` supplies the helper:

   ```bash
   ansible-vault edit    group_vars/all/vault.yml
   ansible-vault view    group_vars/all/vault.yml
   ansible-vault encrypt path/to/new-secret.yml
   ansible-vault decrypt group_vars/all/vault.yml
   ansible-vault rekey   group_vars/all/vault.yml
   ```

   Running from another directory breaks the relative
   `vault_password_file` path — `cd` to the repo root first.

   For the raw password (only when an external tool needs its own
   `--vault-password-file` wiring) run `utils/vault-pass`,
   which prints it and exits 2 if the credential is missing.

3. **Read-only by default.** Prefer `view` over `decrypt` when you only
   need to see a value — `decrypt` rewrites the file in plaintext on
   disk and must be followed by `encrypt`. Never leave a vault file
   decrypted at rest; never commit a decrypted vault.

4. **Mutating safely.** `edit` opens the decrypt→editor→re-encrypt
   round-trip in one step (the safe path for changing a value). After
   any change, confirm the file is still vault-encrypted
   (`head -1` shows `$ANSIBLE_VAULT;...`) before staging. Commit only
   when the user asks, following the repo's commit-style preference (no
   co-author lines).

5. **Hand back.** Report the file touched and the subcommand run (and,
   for `view`, the value asked for — never paste an entire decrypted
   vault into the transcript unless explicitly requested). Vault access
   is the whole job; route deploys and host work to their own skills.

## Known issue

`vars/jc_passwds.enc.yml` does **not** decrypt with the current
`CTTB_VAULT_PASS`; it was encrypted with a different, now-unknown password.
Only `plays/util-hardware-survey-dbg.yml` still loads it. Do not treat a
failure on that file as a credential problem on the operator's side.

## Resources

Self-contained. Drives `ansible-vault` directly, with the password supplied by
`utils/vault-pass` via `ansible.cfg`. No wrapper script, no sibling
files.
