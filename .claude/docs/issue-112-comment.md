Thanks Frank — this is a good catch and the diagnosis is right. Confirming from the repo side, and adding the history so you know what ground has already been covered.

**Confirmed.** `roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` currently declares only three properties under `commands/custom` — `Super_L`, `<Super>l`, `<Super>space` — and no `<Primary><Alt>t`. Since `sudhanix-ux.yml` templates this file *over* `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml` rather than merging into it, every stock binding we don't re-declare is dropped. That is exactly the mechanism, and your reading of the line-17 comment is the right one.

**This is a known failure family, and the terminal binding is a new instance of it.** The overwrite has bitten us three times already:

- #36 / #63 — the Super key not toggling the applications menu. First attempt was a `sudhanix-toggle-appmenu` wrapper, which lost to the popup's `XGrabKeyboard` active grab; resolved by re-pointing `Super_L` at `xfce4-popup-whiskermenu`, whose popup binary toggles on repeat invocation.
- #61 — `Super+L` not locking the session, fixed by declaring `<Super>l` → `xflock4`.
- #33 — the original desktop-polish pass that produced this shortcut set. It is where the overwrite semantics were first written down, and where `<Alt>Tab` got its explicit re-declaration.

So the pattern is established; what nobody did was audit the `commands` channel the way the `xfwm4` channel was audited. Your fourth acceptance criterion is the important one — Ctrl+Alt+T is likely not the only casualty, and I'd rather sweep the channel once against XFCE stock than field these one at a time.

**One thing worth checking before you land the one-property fix.** `exo-open --launch TerminalEmulator` resolves through XFCE's helpers mechanism, and there is no system-wide `/etc/xdg/xfce4/helpers.rc` anywhere in the role. The only places we set `TerminalEmulator=xfce4-terminal` are per-user: `roles/sudhanix-core/files/firstlogin/sudhanix-firstlogin-lib.sh:361` and the Welcome app at `files/welcome/sudhanix-welcome:1104`. #64 pinned `x-terminal-emulator` via `update-alternatives`, which covers Thunar and `.desktop` Exec lines, but that is a different resolution path from `exo-open --launch`.

That matters precisely for the account state in your repro — a fresh LDAP user with no per-user xfconf. If first-login seeding hasn't run yet, `exo-open --launch TerminalEmulator` may raise the "Choose Preferred Application" chooser instead of opening a terminal, which would look like the bug is only half-fixed. Two options: drop a system-wide `helpers.rc` alongside the binding, or bind straight to `xfce4-terminal` and skip the indirection. I lean toward the system-wide `helpers.rc`, since `roles/sudhanix-core/templates/xfce4-appfinder.xml.j2` already depends on the same `exo-open --launch TerminalEmulator` path and has the same exposure.

**On verification.** Your caveat that this is a config finding rather than an observed keypress is the right call, and it doesn't weaken the report — the template is unambiguous. Lab hosts are off-VLAN from where you were; I can put it on a machine when one is reachable, or the `xfconf-query` line in your repro is sufficient once the change is deployed.

Also confirming the stale-config note: `files/config/etc-skel/.config/lxqt/globalkeyshortcuts.conf:20` does bind Ctrl+Alt+T to `/usr/bin/lxterminal`, and it is inert under XFCE. That's leftover from the Lubuntu base and should be cleaned up, though it's cosmetic relative to this.

I've linked the related issues on this one — #36, #63, #61, #64, #33, and #49 (a different menu surface, same "keybind fires, nothing appears" symptom class).
