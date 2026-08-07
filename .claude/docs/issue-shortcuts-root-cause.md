Every keyboard shortcut is dead on a freshly-provisioned Sudhanix 26 host with a fresh user profile. Not "some bindings are missing" — **none of them are active**, including `Alt+Tab`, which our own template explicitly declares.

Verified live on `dvgs-lab3.cttb` (reachable 2026-08-06), against upstream `libxfce4ui` 4.18 source. This supersedes the partial diagnosis in #112.

## Root cause

Two independent defects in `roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` compound into total failure.

**1. The template declares bindings under `custom` but never sets `custom/override`.**

Upstream decides which subtree to read in `libxfce4kbd-private/xfce-shortcuts-provider.c`:

```c
xfce_shortcuts_provider_is_custom (XfceShortcutsProvider *provider)
{
  property = g_strconcat (provider->priv->custom_base_property, "/override", NULL);
  override = xfconf_channel_get_bool (provider->priv->channel, property, FALSE);  /* default FALSE */
  return override;
}
```

and then:

```c
if (G_LIKELY (xfce_shortcuts_provider_is_custom (provider)))
    base_property = provider->priv->custom_base_property;   /* /<name>/custom  */
  else
    base_property = provider->priv->default_base_property;  /* /<name>/default */
```

The fallback for a missing `override` is **`FALSE`**. Our template never writes `override`, so on any profile that hasn't had it set, the provider reads from `/commands/default` and `/xfwm4/default` — and ignores everything we put in `custom`.

**2. The template destroys the `default` subtree it falls back to.**

`sudhanix-ux.yml:100` templates this file over `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`, which is shipped by **`libxfce4ui-common`** (not `xfce4-settings`). The stock file puts *all* its bindings under `default` subtrees. Our replacement contains no `default` subtree at all.

So the provider falls back to `default`, and `default` is empty. Result: zero shortcuts.

## Repro

```bash
# on dvgs-lab3.cttb — simulate a fresh account, exactly as a new LDAP user gets
rm -rf /tmp/freshhome && mkdir -p /tmp/freshhome
HOME=/tmp/freshhome XDG_CONFIG_HOME=/tmp/freshhome/.config \
  dbus-run-session -- xfconf-query -c xfce4-keyboard-shortcuts -lv
```

## Expected

An `override` property set true alongside the custom bindings, or the stock `default` subtree left intact.

## Actual

No `override` property anywhere in the channel:

```
/commands/custom/<Super>l      xflock4
/commands/custom/Super_L       xfce4-popup-whiskermenu
/commands/custom/<Super>space  xfce4-appfinder
/xfwm4/custom/<Alt>Tab         cycle_windows_key
/xfwm4/custom/<Alt><Shift>Tab  cycle_reverse_windows_key
/xfwm4/custom/<Primary>w       close_window_key
/xfwm4/custom/<Super>{Left,Right,Up,Down}  tile_*/maximize_window_key
```

`override` is absent ⇒ `is_custom()` returns FALSE ⇒ provider reads `/commands/default` and `/xfwm4/default` ⇒ both empty ⇒ **no active shortcuts**.

Contrast an *aged* profile (`administrator` on the same host), where `override` has been written at some point — the per-user file carries `override=true` on both subtrees, so the custom bindings do resolve:

```
/commands/custom/override      true
/xfwm4/custom/override         true
/xfwm4/custom/<Alt>Tab         cycle_windows_key
```

**This is why #63 and #61 were reported fixed and are now failing again.** They were verified on a profile that happened to carry `override=true`. Fresh PXE + fresh account does not, so the same bindings are inert. Nothing regressed in the fix; the fix was only ever live on already-customized profiles.

## Blast radius

On a fresh profile, everything is gone. On a profile with `override=true`, our 10 custom bindings work but every stock default is permanently lost, because we deleted the `default` subtree. Casualties confirmed present in the pristine `libxfce4ui-common` file and absent from ours:

| Binding | Stock action | Tracked as |
|---|---|---|
| `<Primary><Alt>t` | `exo-open --launch TerminalEmulator` | #112 |
| `<Alt>Tab` / `<Alt><Shift>Tab` | `cycle_windows_key` | this issue |
| `Super_L` (app menu) | our custom binding, inert | #63 |
| `<Super>l` (lock) | our custom binding, inert | #61 |
| `<Primary>Escape` | `xfdesktop --menu` | cf. #49 |
| `<Primary><Alt>Delete` | `xfce4-session-logout` | — |
| `<Primary><Alt>l` | `xflock4` (stock lock) | — |
| `Print` / `<Alt>Print` / `<Shift>Print` | `xfce4-screenshooter` variants | — |
| `<Super>e`, `<Primary><Alt>f` | `thunar` | — |
| `<Alt>F1` / `<Alt>F2` / `<Alt>F3` | appsmenu / appfinder | — |
| `<Primary><Alt>Escape` | `xkill` | — |
| `<Primary><Shift>Escape` | `xfce4-taskmanager` | — |
| workspace switching, tiling, window ops | many `*_key` actions | — |

## Repo locations

- `roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` — missing `override`; no `default` subtree
- `roles/sudhanix-core/tasks/sudhanix-ux.yml:100` — the task that replaces the stock file
- pristine original: `apt-get download libxfce4ui-common` → `etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`

## Acceptance criteria

- [ ] `<property name="override" type="bool" value="true"/>` is declared inside **both** the `commands/custom` and `xfwm4/custom` subtrees
- [ ] The stock `default` subtrees from `libxfce4ui-common` are carried in the template, so fallback is non-empty and stock bindings survive
- [ ] The fresh-profile repro above lists `override true` and resolves every intended binding
- [ ] On a freshly-PXE'd host with a brand-new LDAP account: `Alt+Tab` cycles windows, `Super` toggles the menu, `Super+L` locks, `Ctrl+Alt+T` opens a terminal
- [ ] Decide the policy for the stock bindings we do **not** want (e.g. whether `<Primary><Alt>l` should coexist with `<Super>l`)
- [ ] Existing profiles carrying a stale per-user `xfce4-keyboard-shortcuts.xml` are considered — migrate or leave alone

## Workaround

Per user, until fixed:

```bash
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/override -n -t bool -s true
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/override    -n -t bool -s true
```

That revives the 10 bindings we declare. It does **not** bring back the stock defaults — those need the template fix.

## Where to look first

The one-line `override` addition is necessary but not sufficient; without restoring the `default` subtree, hosts keep losing every stock binding. Treat both halves as the fix.

## Context

Surfaced 2026-08-06 while triaging #112 (Frank's Ctrl+Alt+T report). His diagnosis — that the template replaces rather than extends the stock file — was correct but incomplete: the missing `<Primary><Alt>t` is one casualty of a defect that takes out the entire channel. The `Alt+Tab` report is what falsified the "just add the missing binding" reading, since `<Alt>Tab` *is* declared in our template and still does not fire.
