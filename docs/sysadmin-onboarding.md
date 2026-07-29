# Sysadmin Onboarding

Getting a new workstation from bare machine to a verified Ansible run against the CTTB fleet.

Follow the sections in order. Each one ends in something you can check, so if a later step fails you know the earlier ones were sound. Budget about 45 minutes, most of it waiting on package installs.

This guide assumes you are **on the campus network** — wired, or CTTB wifi. The `10.11.x.y` addresses are not routable from outside; remote access is a separate step covered in §11.

---

## 1. What you need before you start

Three things, and two of them have to come from someone else:

| What | How you get it |
|---|---|
| Campus network access | Wired ethernet or CTTB wifi. |
| The `CTTB_VAULT_PASS` value | From an existing sysadmin, out of band — not email, not chat history. |
| An existing admin to vouch for your SSH key | Their key is already trusted by the fleet; yours is not. §8 explains why this is unavoidable. |

You do **not** need an LDAP account or sudo on any host yet. Those come later and are not prerequisites for the setup below.

---

## 2. Install Ansible

### macOS

1. Install Homebrew if you don't have it:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
2. Install Ansible:
   ```bash
   brew install ansible
   ```
3. Verify:
   ```bash
   ansible --version
   ```

### Windows (WSL)

1. Install WSL with a Ubuntu/Debian distro from PowerShell (admin): `wsl --install`, then reboot and complete the distro setup.
2. Inside the WSL shell, update packages and install:
   ```bash
   sudo apt update && sudo apt install -y ansible
   ```
3. Verify:
   ```bash
   ansible --version
   ```

Everything from here on runs **inside the WSL shell**, never in PowerShell. See §12 for the WSL-specific traps.

### Debian Linux

1. Update the package index:
   ```bash
   sudo apt update
   ```
2. Install:
   ```bash
   sudo apt install -y ansible
   ```
3. Verify:
   ```bash
   ansible --version
   ```

### If your Ansible is too old

The apt-packaged Ansible on Debian stable can lag several versions behind. If you need current releases on Debian or WSL, use pipx instead:

```bash
sudo apt install pipx && pipx install --include-deps ansible
```

That pulls the latest from PyPI while keeping it isolated from system Python. The `--include-deps` flag matters: it installs the full `ansible` package (which bundles collections), not bare `ansible-core`.

---

## 3. Install the collections

```bash
ansible-galaxy collection install -r requirements.yml
```

This repo uses `ansible.posix`, `community.general`, and `community.mysql`. The full `ansible` package bundles them, so if you installed via `brew install ansible` or `apt install ansible` you are probably already covered — run the command anyway, it is idempotent and costs seconds.

**Do not skip this if you installed `ansible-core`.** Modern `ansible-core` ships zero collections, and the failure mode is actively misleading: a play aborts with `couldn't resolve module/action 'synchronize'` naming the *task*, never the missing collection. People lose an hour to this.

Check:

```bash
ansible-galaxy collection list | grep -E 'ansible\.posix|community\.(general|mysql)'
```

---

## 4. Clone the repo and set up the environment

```bash
git clone <repo-url> ~/cttb-ansible
cd ~/cttb-ansible
source utils/setup-env
chmod +x .claude/sysadmin/vault-pass .claude/sysadmin/cttb-ct.sh
```

**`source utils/setup-env` is mandatory, not a convenience.** `ansible.cfg` interpolates `$ANSIBLE_ROLES`, `$ANSIBLE_HOSTS`, and `$ANSIBLE_TMP`; a fresh clone without those exported has broken role and inventory paths. It must be `source`d, not executed — running it in a subshell exports nothing. Add it to your shell profile, or use the `utils/pb`, `utils/ar`, `utils/rc` wrappers, which source it themselves.

**Always run Ansible commands from the repository root.** `ansible.cfg` uses relative paths, including the vault helper you are about to set up.

---

## 5. Store your credentials

Secrets are read from your platform's credential store — never from a file in the repo, and (for the vault password) never from an environment variable.

Store the `CTTB_VAULT_PASS` value you got in §1:

**macOS**
```bash
security add-generic-password -s CTTB_VAULT_PASS -a "$USER" -w
```

**Windows / WSL**

WSL usually has no D-Bus keyring, so use the file store:
```bash
mkdir -p ~/.config/cttb/secrets
printf '%s' '<value>' > ~/.config/cttb/secrets/CTTB_VAULT_PASS
chmod 600 ~/.config/cttb/secrets/CTTB_VAULT_PASS
```

**Debian Linux** (with a desktop session)
```bash
sudo apt install -y libsecret-tools
secret-tool store --label=CTTB_VAULT_PASS service CTTB_VAULT_PASS
```
On a headless Debian box, use the file-store commands above instead.

Check — this should print the password and exit 0:

```bash
.claude/sysadmin/vault-pass
```

If it exits 2, it tells you exactly which command to run. It deliberately never prints an empty string: handing `ansible-vault` a blank password produces a confusing "decryption failed" rather than "your credential is missing".

Now confirm Ansible itself picks it up. `ansible.cfg` sets `vault_password_file`, so no flags are needed anywhere:

```bash
ansible-vault view host_vars/wiki-2404/wiki_vault.yml
```

> **Known issue.** `vars/jc_passwds.enc.yml` will **not** decrypt — it was encrypted with an older, now-unknown password. That is a pre-existing repo defect, not a problem with your setup. Only `plays/util-hardware-survey-dbg.yml` still loads it.

The wiki and LDAP tools use the same layer, with these services: `WIKI_CTTB_BOT_USER`, `WIKI_CTTB_BOT_PASSWD`, `CTTB_LDAP_USERNAME`, `CTTB_LDAP_PASSWD`. Add them the same way when you need `/wiki-author` or `/ldap`; they are not needed for a first run.

---

## 6. Set up `~/.ssh/config`

The `cttb-ct.sh` toolkit resolves host aliases (`srv-vm`, `srv-nas`, `wiki`, …) out of your SSH config. Without them every command fails with "Could not resolve hostname".

Add this as the **first line** of `~/.ssh/config` — `Include` has to precede any `Host` block:

```
Include ~/ansible-cttb/docs/ssh_config.example
```

Including by reference rather than copy-pasting means updates to the host table reach you with a `git pull`.

Check:

```bash
ssh -G srv-vm | head -3      # should resolve to hostname 10.11.1.3, user administrator
```

---

## 7. Generate your keypair

```bash
ssh-keygen -t ed25519 -C "<your-name>@cttb"
```

Take the default location (`~/.ssh/id_ed25519`). Use a passphrase; `ssh-agent` will hold it so you type it once per session.

On WSL, the key **must** live in the WSL filesystem (`~/.ssh`), not under `/mnt/c/...` — see §12.

---

## 8. Enroll your key

This is the part that trips people up, so it is worth stating plainly:

> **You cannot enroll yourself.** Your key is on no host, so you have no way in. Someone whose key is *already* trusted has to install yours. Your access is a consequence of their access.

### The durable path — how it should normally happen

1. Copy your **public** key (`~/.ssh/id_ed25519.pub` — never the private one) into the repo:
   ```bash
   cp ~/.ssh/id_ed25519.pub roles/common/files/ssh_keys/<your-name>.pub
   ```
2. Open a pull request with just that file.
3. An existing sysadmin reviews and merges it, then — from **CTTB_TRUSTED_HOST** (the designated originator machine whose key is already trusted fleet-wide; currently `rui-desktop2`) — runs the distribution play:
   ```bash
   ansible-playbook plays/distribute-ssh-keys.yml --check --diff   # preview
   ansible-playbook plays/distribute-ssh-keys.yml                  # distribute
   ```
   **Their** already-trusted key authorizes the SSH connection that installs **yours**; the play needs no become password because it edits `administrator`'s own `authorized_keys`. (A full `common`-role run distributes keys too — the play is the lightweight path that touches nothing else.)

Every `*.pub` in `roles/common/files/ssh_keys/` is installed into `administrator`'s `authorized_keys` fleet-wide, so this is a one-file change with no task edits.

Two things to know about it:

- **It never revokes.** The task uses `state: present`, so deleting a `.pub` from that directory does *not* remove the key from any host. Revoking access is a separate, deliberate operation.
- **It does not cover freshly imaged hosts.** `roles/netinstall-2404` and `roles/netinstall` still carry their own inlined copies of the old keys. A key added today reaches existing hosts on the next `common` run, but a host PXE-imaged tomorrow will not have it until those templates are updated too.

### The stopgap path — one host, right now

Freshly imaged hosts still allow password authentication (`allow-pw: true` in the autoinstall profile), so while that window is open:

```bash
ssh-copy-id administrator@10.11.30.60
```

This gets you onto **one** host with the account password. It is not enrollment — do the pull request anyway.

### LXC containers — no password path at all

The containers have no sshd, so there is nothing to `ssh-copy-id` into. The only way in is through an already-trusted admin on the parent host:

```bash
# containers on srv-vm — no sudo
ssh -t srv-vm -- lxc exec ldap --

# containers on srv-nas — sudo IS required
ssh -t srv-nas -- sudo lxc exec pxe --
```

**That asymmetry is real and is the single most confusing thing about this topology.** `srv-nas` needs `sudo` because the login user there cannot read `/etc/lxc`; `srv-vm` does not. `cttb-ct.sh` encodes it for you — prefer `.claude/sysadmin/cttb-ct.sh shell <alias>` over hand-typing either form.

---

## 9. Privilege escalation on managed hosts

`administrator` (uid 999) is an **ordinary sudoer**, not a passwordless one. Any play that touches privileged state needs a become password — add `--ask-become-pass` to whatever play you have been asked to run:

```bash
ansible-playbook plays/<play>.yml --limit <host> --check --diff --ask-become-pass
```

(`--check --diff` previews without changing anything; drop it only when you mean to deploy. Nothing in this guide requires you to deploy anything — which play to run is a task question, not an onboarding one.)

Members of the LDAP `cn=it` group get sudo directly (`/etc/sudoers.d/it-group`, `%it ALL=(ALL:ALL) ALL`), also password-required. If you need personal sudo (as your own LDAP user, rather than the shared `administrator` account), ask an existing sysadmin to add your LDAP account to `cn=it`.

> **Handle `CTTB_VAULT_PASS` as a high-privilege credential.** Store it only in your platform credential store or the 0600 file, never in a shell history, a chat message, or a file in the repo. Ask an existing sysadmin before sharing it onward.

---

## 10. Verify

Work down this list. Each step depends only on the ones above it, so the first failure tells you where to look.

```bash
cd ~/cttb-ansible && source utils/setup-env

# 1. Ansible and collections
ansible --version
ansible-galaxy collection list | grep -E 'ansible\.posix|community\.(general|mysql)'

# 2. Vault credential resolves
.claude/sysadmin/vault-pass >/dev/null && echo "vault password OK"

# 3. Ansible picks it up with no flags
ansible-vault view host_vars/wiki-2404/wiki_vault.yml >/dev/null && echo "vault wiring OK"

# 4. Playbooks parse
ansible-playbook --syntax-check plays/sudhanix26-rollout-stage2.yml

# 5. SSH aliases resolve
ssh -G srv-vm | head -3

# 6. You can reach a host (needs §8 to have completed)
ansible -i inventory/sudhanix26_hosts.ini <a-host>.cttb -m ping

# 7. Container access through the jump chain
.claude/sysadmin/cttb-ct.sh exec ldap hostname
```

Step 6 succeeding is the real milestone: it proves install, collections, SSH config, and key enrollment all work together.

Before making changes to a real host, dry-run first — `--check --diff` shows what *would* change without touching anything.

---

## 11. Remote access (optional)

Everything above assumes campus network. For off-campus work, `cttb` is a Tailscale subnet router running on srv-vm that advertises `10.11.0.0/16` — once you are on the tailnet, the same `10.11.x.y` addresses work unchanged.

You need a tailnet invitation from an existing admin. Note that `TODO.md` records ProxyJump over Tailscale as intermittent; if a jump fails remotely but works on campus, that is the known issue, not your config.

---

## 12. WSL-specific traps

Four things that will bite you specifically on WSL:

**Keys on `/mnt/c` are rejected.** Files on the Windows drive inherit `0777` under DrvFs, and `ssh` refuses a private key that permissive — `chmod` there does not stick. Keep keys in the WSL filesystem at `~/.ssh`.

**`ssh-agent` does not persist.** Each new WSL shell starts without one, so your passphrase is re-prompted constantly. Start it from your profile:
```bash
# ~/.bashrc
[ -z "$SSH_AUTH_SOCK" ] && eval "$(ssh-agent -s)" >/dev/null
```

**Clone from inside WSL.** A repo cloned with Windows git gets CRLF line endings, and `bash` fails on `utils/setup-env` with `$'\r': command not found`.

**Clock drift after the host sleeps.** WSL's clock can fall behind, which breaks TLS handshakes with confusing certificate errors. Fix with `sudo hwclock -s`.

---

## 13. Troubleshooting

| Symptom | Cause |
|---|---|
| `couldn't resolve module/action 'synchronize'` | Collections not installed — §3. The error names the task, not the collection. |
| `ERROR! the role 'common' was not found` | `utils/setup-env` not sourced, or you are not in the repo root — §4. |
| `vault-pass` exits 2 | Credential not in the store. Its stderr names the exact command — §5. |
| `Decryption failed` on `vars/jc_passwds.enc.yml` | Pre-existing repo defect, not your setup — §5. |
| `Could not resolve hostname srv-vm` | `~/.ssh/config` missing the `Include` — §6. |
| `Permission denied (publickey)` on a managed host | Your key is not enrolled yet — §8. |
| `Missing sudo password` | Add `--ask-become-pass` — §9. |
| Works on campus, fails remotely | Tailscale ProxyJump flakiness — §11. |

---

## See also

- `README.md` — repo layout, inventory, roles, playbooks
- `PROJECT.md` — network architecture and role subsystems
- `DEPLOYMENT.md` — the staged PXE rollout procedure
- `CLAUDE.md` — the sysadmin skill catalog and toolkit reference
