# Proposal: the Sudhanix 26 keyboard shortcut set (cttb-ansible#114)

Draft on branch `draft/gh-114-keyboard-shortcuts`. **Not on `main`** — landing it
changes every desktop's shortcut table on the next `sudhanix-ux` run, so it
wants a decision on the binding set first.

## Correction to the issue as filed

#114's acceptance criteria say to restore the stock `default` subtree so the
fallback is non-empty. That is worth doing, but it is **not** what revives the
stock bindings. Upstream:

```c
xfce_shortcuts_provider_get_shortcuts (...)
{
  properties = xfconf_channel_get_properties (provider->priv->channel,
                                              provider->priv->custom_base_property);
  ...
}
```

The live set is enumerated from `custom` and only `custom`. `default` serves the
Settings GUI's "Reset to Defaults" and the unset-override fallback path. So every
binding that must actually work has to be written into `custom`, alongside
`override = true`. The draft does both: `custom` carries the full working set,
`default` carries upstream verbatim.

## What the draft contains

| Channel | stock `default` | live `custom` | `override` |
|---|---|---|---|
| `commands` | 21 | 23 | `true` |
| `xfwm4` | 60 | 65 | `true` |

Verified well-formed and duplicate-free by parsing the rendered template.

## Decisions I made — please confirm or overrule

**1. `<Primary>Escape` is dropped** (the only stock binding not carried).
Upstream points it at xfdesktop's menu flag, which is the deterministic SIGSEGV
in #49. Binding a key to it hands users a reliable way to crash xfdesktop. My
call: leave it out until #49 is fixed, then restore. *Overrule if you would
rather ship it and treat the crash as visible.*

**2. `<Alt>F1` is re-pointed** from `xfce4-popup-applicationsmenu` to
`xfce4-popup-whiskermenu`. The applicationsmenu plugin is not the menu in our
panel, so the stock binding would open a menu users never see otherwise. This
keeps `<Alt>F1` and `Super` opening the same thing.

**3. Duplicate lock and terminal bindings are kept.** Stock `<Primary><Alt>l`
coexists with our `<Super>l` (both `xflock4`); stock `<Super>r` and `<Alt>F2`/
`<Alt>F3` coexist with our `<Super>space` (all appfinder). Users arriving from
either convention find something that works. *Overrule if you want a single
canonical binding per action.*

**4. All 60 stock `xfwm4` bindings are carried**, including workspace switching
(`<Primary>F1`–`F12`, `<Primary><Alt>` arrows), window ops (`<Alt>F4`–`F12`),
and keypad tiling. Our five macOS-style additions (`<Super>` arrows, `<Primary>w`)
sit alongside them rather than replacing them.

## Testing before this lands

It cannot be verified from config alone — that is precisely how #114 stayed
hidden. On a host with the template deployed:

```bash
# fresh profile, exactly what a new LDAP user gets
rm -rf /tmp/freshhome && mkdir -p /tmp/freshhome
HOME=/tmp/freshhome XDG_CONFIG_HOME=/tmp/freshhome/.config \
  dbus-run-session -- xfconf-query -c xfce4-keyboard-shortcuts -lv | grep override
```

Then at a real seat with a brand-new account: `Alt+Tab`, `Super`, `Super+L`,
`Ctrl+Alt+T`, `Print`.

Existing profiles carrying a stale per-user
`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml` are
still an open question in #114 — this draft does not migrate them.
