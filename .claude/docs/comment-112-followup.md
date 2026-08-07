Frank — following up on my earlier comment, and correcting part of it. A lab host came back on the network, so I was able to verify on real hardware rather than reason from the config. Your mechanism is right but the scope is considerably worse, and the fix you proposed will not be sufficient on its own.

**What forced the re-think.** JC reported that `Alt+Tab` is also dead. `<Alt>Tab` *is* declared in our template — so "the template dropped the binding" cannot explain it, and the single-property fix would not have helped.

**The actual root cause.** Upstream `libxfce4kbd-private/xfce-shortcuts-provider.c` picks the subtree to read like this:

```c
override = xfconf_channel_get_bool (channel, ".../custom/override", FALSE);  /* absent ⇒ FALSE */
...
if (is_custom (provider)) base_property = custom_base_property;   /* /<name>/custom  */
else                      base_property = default_base_property;  /* /<name>/default */
```

Our template writes every binding under `custom` and never sets `override`. So on any profile that hasn't had `override` written, the provider ignores `custom` entirely and reads `default` — which our template also destroyed, since the file we replace (shipped by **`libxfce4ui-common`**, not `xfce4-settings`) is where the stock `default` subtree lives.

Net effect on a fresh account: not one missing binding, but **no keyboard shortcuts at all**.

Verified on `dvgs-lab3.cttb`, simulating an account with no prior xfconf state:

```bash
rm -rf /tmp/freshhome && mkdir -p /tmp/freshhome
HOME=/tmp/freshhome XDG_CONFIG_HOME=/tmp/freshhome/.config \
  dbus-run-session -- xfconf-query -c xfce4-keyboard-shortcuts -lv
```

No `override` property anywhere, and no `/commands/default` or `/xfwm4/default` entries at all. On the aged `administrator` profile on the same box, `override=true` is present and our custom bindings do resolve — which is why this passed verification when #63 and #61 were originally closed.

**Where this leaves your report.** The finding stands and your repro is the right one; I've made it a sub-issue of #114, which carries the root cause and the full list of casualties. Two amendments:

1. Adding `<Primary><Alt>t` to `commands/custom` will still do nothing until `custom/override` is set true. Both halves are needed.
2. Your fourth acceptance criterion — audit the channel against stock — turned out to be the whole problem rather than a follow-up. The stock `default` subtree contains roughly two dozen bindings we are currently discarding: screenshots, `xkill`, task manager, session logout, workspace switching, `<Primary>Escape` → `xfdesktop --menu` (which is also interesting for #49).

Also worth noting for #114: my earlier point about `exo-open --launch TerminalEmulator` having no system-wide `helpers.rc` still holds, and is a genuinely separate problem from this one. It just won't be the thing you hit first.

Good catch, and the "not verified on live hardware" caveat was the right call to make — it's what kept the partial diagnosis from being taken as settled.
