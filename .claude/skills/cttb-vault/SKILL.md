---
name: cttb-vault
user-invocable: true
argument-hint: "<edit|view|encrypt|decrypt|rekey> <vault file>"
description: >
  Run any `ansible-vault` subcommand against CTTB vault files through
  `.claude/sysadmin/cttb-vault.sh`, which sources the vault password
  from macOS Keychain (`CTTB_VAULT_PASS`) so there is never a password
  prompt or a plaintext password on disk. Triggers on "edit
  group_vars/all/vault.yml", "decrypt the vault file", "view a vaulted
  var", "rekey the vault", `/cttb-vault <subcmd> <file>`, or any agent
  step that must read or change an encrypted Ansible value. One job:
  authenticated ansible-vault access. It does not deploy or run plays.
---

## When to apply

Apply whenever an encrypted Ansible value must be read or changed:
inspecting a vaulted variable, editing `group_vars/all/vault.yml`,
encrypting a new secret file, decrypting for a one-off check, or
rekeying. Do not apply for non-vault YAML edits (use `Edit`
directly), for running playbooks, or for the sudo/SSH credentials a
deploy needs at runtime (those resolve from Keychain at play time).

## Procedure

1. **Confirm the target.** Identify the exact vault file path
   (canonical: `group_vars/all/vault.yml`). Vault files are
   ansible-vault-encrypted; editing them with a plain editor corrupts
   them — always go through the wrapper.

2. **Run the subcommand.** Pass any `ansible-vault` subcommand; the
   wrapper supplies the Keychain password automatically:

   ```bash
   .claude/sysadmin/cttb-vault.sh edit    group_vars/all/vault.yml
   .claude/sysadmin/cttb-vault.sh view    group_vars/all/vault.yml
   .claude/sysadmin/cttb-vault.sh encrypt path/to/new-secret.yml
   .claude/sysadmin/cttb-vault.sh decrypt group_vars/all/vault.yml
   .claude/sysadmin/cttb-vault.sh rekey   group_vars/all/vault.yml
   ```

   For the raw password (only when a tool needs `--vault-password-file`
   wiring) use `.claude/sysadmin/vault-pass.sh`, which prints
   `CTTB_VAULT_PASS`.

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

## Resources

Self-contained. Drives two existing helpers:
`.claude/sysadmin/cttb-vault.sh` (the `ansible-vault` wrapper) and its
backing `.claude/sysadmin/vault-pass.sh` (Keychain → `CTTB_VAULT_PASS`).
No new scripts, no sibling files.
