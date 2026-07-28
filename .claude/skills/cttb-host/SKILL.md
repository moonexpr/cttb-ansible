---
name: cttb-host
user-invocable: true
argument-hint: "<host/container alias> [command...]"
description: >
  Open a shell on, or run a one-shot command against, any registered
  CTTB host or container via `.claude/sysadmin/cttb-ct.sh`. SSH chains
  and ProxyJump are pre-wired (`~/.ssh/config`, the script's
  `ssh_chain()` case). Triggers on "get into wiki-2404", "shell into
  the LDAP container", "run X on srv-vm", "what's on pxe", `/cttb-host
  <alias>`, or any agent step that needs to execute on a CTTB box
  rather than locally. One job: reach a CTTB host. It does not edit
  files or vault — it gives you the shell.
---

## When to apply

Apply whenever the action must run **on a CTTB host/container**, not on
the workstation: inspecting a service, tailing a log, checking a
package version, running a one-off remote command, or an interactive
shell. Do not apply for local Ansible runs, vault edits (use
`/cttb-vault`), wiki API edits (use `/wiki-author` / the `wiki` CLI),
or LDAP queries (use `/ldap`) — those have their own tooling that
already handles the remote leg.

## Procedure

1. **Resolve the alias.** If the target alias is unknown, list the
   registered ones:

   ```bash
   .claude/sysadmin/cttb-ct.sh list
   ```

   Common aliases: `wiki` (wiki-2404, 10.11.1.34), `ldap`, `srv-vm`,
   `pxe`. If the host isn't registered, add a case to `ssh_chain()` at
   the top of `.claude/sysadmin/cttb-ct.sh` rather than hand-rolling an
   ssh+lxc chain (per the standing "use cttb-ct.sh" preference).

2. **One-shot vs. interactive.** Pick the form that matches the need:

   - One command, output captured (the default for agent use):
     ```bash
     .claude/sysadmin/cttb-ct.sh exec <alias> <cmd...>
     ```
   - Interactive session (the default when the user types `/cttb-host
     <alias>` with no command):
     ```bash
     .claude/sysadmin/cttb-ct.sh shell <alias>
     ```

3. **Run it.** Use `exec` for anything an agent needs to read back;
   route large output through context-mode per the global Bash policy.
   For multi-step remote work, prefer several `exec` calls over a long
   shell heredoc so each step's result is observable.

4. **Privilege.** Where a remote step needs `sudo`, obtain the CTTB sudo
   password from your platform credential store rather than the
   inventory — the `all.with-password` value there is stale, do not
   use it.

5. **Hand back.** Report the host reached and the command's result.
   Reaching the shell is the whole job — do not drift into editing
   config, vault, or wiki content from inside the session; route those
   to their owning skill.

## Resources

Self-contained. The skill drives one existing helper,
`.claude/sysadmin/cttb-ct.sh` (host/container registry + SSH-chain
wrapper, credentials via `~/.ssh/config` and macOS Keychain). It writes
no new scripts and loads no sibling files.
