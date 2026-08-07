Reopened — this is live again on freshly-provisioned hosts.

**This is not a regression of the original fix.** The binding is still declared in `roles/sudhanix-core/templates/xfce4-keyboard-shortcuts.xml.j2` and it is still correct. It is inert because the provider never reads the subtree it lives in.

Upstream `libxfce4kbd-private` selects between `/<name>/custom` and `/<name>/default` on the boolean `/<name>/custom/override`, defaulting to **FALSE** when that property is absent. Our template never writes `override`, so the provider falls back to `/<name>/default` — and our template also replaced the stock `libxfce4ui-common` file that supplied `default`, leaving it empty. Fresh profile ⇒ no shortcuts at all.

The reason this looked fixed at the time: verification happened on a profile that already carried `override=true` (it gets written once a user opens the Keyboard settings dialog). On such a profile the custom bindings resolve correctly. A freshly-PXE'd host with a brand-new LDAP account has no such property, so the same config is dead.

Verified on `dvgs-lab3.cttb` 2026-08-06, with the fresh-profile repro and the upstream source excerpt in #114.

Per-user workaround until the template is fixed:

```bash
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/override -n -t bool -s true
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/override    -n -t bool -s true
```

Now tracked as a sub-issue of #114, which carries the root cause and the full blast radius. Keeping this open separately so the specific binding gets re-verified on a fresh account rather than assumed fixed when #114 lands — that assumption is exactly what let this sit unnoticed.
