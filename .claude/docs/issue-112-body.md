## Repro

On a Sudhanix 26 workstation provisioned by `sudhanix-core` (fresh PXE install, or any host that has had the `sudhanix-ux` tag applied), log in as an LDAP user whose home has no pre-existing per-user xfconf override and press <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>T</kbd>.

```bash
# on the workstation
xfconf-query -c xfce4-keyboard-shortcuts -lv | grep -i alt
grep -c 'Primary.*Alt.*t' /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
```

## Expected

<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>T</kbd> opens a terminal — the XFCE stock binding `<Primary><Alt>t` → `exo-open --launch TerminalEmulator`. This is the near-universal Linux desktop convention and the shortcut users arrive expecting.

## Actual

Nothing happens; no terminal opens. The deployed system-wide shortcuts file declares no `<Primary><Alt>t` property at all.

`roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` is 28 lines and defines exactly two subtrees:

- `commands/custom` — `Super_L`, `<Super>l`, `<Super>space`
- `xfwm4/custom` — `<Alt>Tab`, `<Alt><Shift>Tab`, `<Super>Left/Right/Up/Down`, `<Primary>w`

`sudhanix-ux.yml` templates this over `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`, i.e. it **replaces** the distribution's defaults file rather than extending it, so every stock binding not re-declared in the template is dropped.

This is the same failure mode already encountered and fixed for the window manager channel — the template's own comment at line 17 reads:

> Task switcher. Replacing xfwm4/custom in xfconf wipes the upstream `<Alt>Tab` default, so bind explicitly here.

The identical reasoning was never applied to the `commands` channel.

A sweep of all 728 non-vendored files under `roles/` finds no other terminal binding. The only `Ctrl+Alt+T` in the repo is `roles/sudhanix-core/files/config/etc-skel/.config/lxqt/globalkeyshortcuts.conf:20`, which launches `lxterminal` under LXQt — dead config in an XFCE session.

**Not verified on live hardware.** No lab workstation was reachable at the time of filing (`dvgs-lab1.cttb` resolves to 10.11.9.21 but has no route; the DVBS/DRBU lab short names do not resolve off-VLAN). The finding is from the deployed configuration, not an observed keypress — the `xfconf-query` line above is the confirming test.

## Repo locations

- `/home/fliu/cttb-ansible/roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` — the template; missing the binding
- `/home/fliu/cttb-ansible/roles/sudhanix-core/tasks/sudhanix-ux.yml:109-118` — the task that overwrites the system defaults file
- `/home/fliu/cttb-ansible/roles/sudhanix-core/files/config/etc-skel/.config/lxqt/globalkeyshortcuts.conf:20` — stale LXQt binding, inert on XFCE

## Acceptance criteria

- [ ] `<Primary><Alt>t` is declared in `xfce4-keyboard-shortcuts.xml.j2` under `commands/custom`
- [ ] On a freshly-PXE'd host with a fresh account, <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>T</kbd> opens a terminal window
- [ ] `xfconf-query -c xfce4-keyboard-shortcuts -lv` lists the binding after `sudhanix-ux` runs
- [ ] The rest of the channel is audited once against XFCE stock defaults for other bindings silently dropped by the same overwrite
- [ ] A user with a pre-existing `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml` is considered — decide whether to migrate or leave per-user overrides alone

## Workaround

Per user, until fixed — open a terminal from the dock or the lotus menu, or bind it by hand:

```bash
xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Primary><Alt>t' \
  -n -t string -s 'exo-open --launch TerminalEmulator'
```

## Where to look first

`roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2`, the `commands/custom` block. The fix is one property:

```xml
<property name="&lt;Primary&gt;&lt;Alt&gt;t" type="string" value="exo-open --launch TerminalEmulator"/>
```

`exo-open --launch TerminalEmulator` (rather than a hardcoded `xfce4-terminal`) keeps this consistent with the default-terminal-emulator handling from #64.

## Context

Found while verifying the claims in the `Sudhanix 26 User Manual` wiki page during a pass that rendered it to PDF for distribution. The manual's password-change section (§2.3) instructs users to open a Terminal and run `passwd`; checking whether the obvious route to a terminal still worked surfaced this. It matters because the missing shortcut compounds a second gap — there is no GUI or menu entry for changing a password anywhere in the roles, so the terminal is the only route to a routine task every user needs.


## Related issues

All of the below share one root surface: `roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` is a **full replacement** of `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`, so any binding it does not re-declare is silently dropped.

**Leader (Super) key → menu**

- #36 — Super-key toggle: GTK keyboard-grab masks xfwm4 keybind on second press. The `sudhanix-toggle-appmenu` wrapper was defeated by the applicationsmenu popup's `XGrabKeyboard`; resolved via Path B (whiskermenu).
- #63 — `Super` alone does not toggle the application menu. Already a sub-issue of #36; closed by 93f6cf61, which re-pointed `Super_L` at `xfce4-popup-whiskermenu`.
- #49 — `xfdesktop --menu`: deterministic SIGSEGV at `xfdesktop+0x1c768`. Open. A different menu surface (desktop right-click, not the panel menu), but the same user-visible symptom class: a menu keybind fires and no menu appears.

**Other bindings in the same template**

- #61 — `Super+L` not locking the session. Same template, same "binding absent or inert" shape; closed by the same commit that fixed #63.
- #64 — xfce4-terminal not set as the system default terminal emulator. Directly load-bearing here: the fix proposed in this issue dispatches through `exo-open --launch TerminalEmulator`, whose resolution path #64 established.
- #33 — Sudhanix desktop polish, noon test 2026-05-07. The origin umbrella for this shortcut set (`<Primary>w`, the Super toggle, `Super+Space`) and the first place the overwrite semantics were documented.
