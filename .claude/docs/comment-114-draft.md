Draft ready on branch `draft/gh-114-keyboard-shortcuts` (commit `033ac9a3`), deliberately **not** on `main` — landing it rewrites every desktop's shortcut table on the next `sudhanix-ux` run, so the binding set wants a look first. Rationale and the decisions I made: `.claude/docs/proposal-gh-114-shortcut-set.md`.

**One correction to the acceptance criteria above.** Criterion 2 says to carry the stock `default` subtrees so the fallback is non-empty. Worth doing, but it is not what revives the stock bindings:

```c
xfce_shortcuts_provider_get_shortcuts (...)
{
  properties = xfconf_channel_get_properties (provider->priv->channel,
                                              provider->priv->custom_base_property);
```

The live set is enumerated from `custom`, and only `custom`. `default` feeds the Settings GUI's "Reset to Defaults" and the unset-override path. So **every binding that must work has to be written into `custom`**, next to `override = true`. Adding one to `default` alone does nothing. The draft puts the full working set in `custom` and keeps `default` verbatim from upstream.

Shape of it, verified by parsing the rendered template (well-formed, no duplicate keys):

| Channel | stock `default` | live `custom` | `override` |
|---|---|---|---|
| `commands` | 21 | 23 | `true` |
| `xfwm4` | 60 | 65 | `true` |

Two judgement calls worth a second opinion:

- **`<Primary>Escape` dropped** — the only stock binding not carried. Upstream points it at xfdesktop's menu flag, the deterministic SIGSEGV in #49; binding a key to it hands users a reliable way to crash xfdesktop. Restore once #49 is fixed.
- **`<Alt>F1` re-pointed** to `xfce4-popup-whiskermenu`, since `xfce4-popup-applicationsmenu` is not the menu in our panel.

Duplicate lock and appfinder bindings from upstream (`<Primary><Alt>l`, `<Super>r`, `<Alt>F2`/`F3`) are kept alongside ours, so users arriving from either convention get something that works.

Still open and not addressed by this draft: profiles carrying a stale per-user `xfce4-keyboard-shortcuts.xml` (criterion 6). And this cannot be signed off from config alone — that is exactly how the bug survived. It needs a fresh LDAP account at a real seat pressing the keys.
