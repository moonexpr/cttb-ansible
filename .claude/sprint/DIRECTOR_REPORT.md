# Director Report — Sprint 1 — 2026-04-16

## Summary
All 3 phases completed. Version-forked roles (`common-*`, `desktop-*`) unified into single roles with Red Hat GPA dispatch pattern (include_vars + first_found). Wallpaper rotation and per-site login background foundation added. Inventory cleaned of 6 historical snapshot files.

## Proxy Decisions Made On Your Behalf
| Phase | Task | Decision | Rationale | Reversible? |
|-------|------|----------|-----------|-------------|
| 1 | 1.1 | Dropped pre-20.04 tasks (apt_key refresh, net udev rule, set hostname, install aptitude) | Identified as Ubuntu 14.04/16.04/18.04 artifacts — all EOL | Yes — tasks preserved in `.deprecated/` roles |
| 2 | 2.1 | Used desktop-22.04 as base, not desktop-20.04 | 22.04 has modern Ansible syntax (loop, systemd module, signed-by repos) and was built for the 24.04 upgrade path | Yes — `.deprecated/desktop-20.04/` preserved |
| 2 | 2.1 | Old LXDE-era `desktop` role preserved as `desktop-old` in `.deprecated/` | Completely different desktop environment (LXDE vs LXQt), not mergeable | Yes |
| 2 | 2.2 | Chose cron + feh for wallpaper rotation | Lightest option for Lubuntu/LXQt — no additional daemon, available in Ubuntu repos | Yes — mechanism is one task file |

## Temporary Solutions Applied
None.

## Deferred Items — Needs Your Input
- **host_vars/srv-gw tab character:** Line 87 has a tab that breaks `ansible-inventory --list`. Quick fix but outside sprint scope. Fix when convenient?
- **Wallpaper images:** 16 placeholder California nature images were downloaded via URLs. Verify the images are acceptable quality/content when you can view them on a display.
- **Per-campus login images:** The existing campus-specific login images (anime girl, lotus, buddhist sticker) need to be identified and mapped to group_vars. The `desktop_login_background` variable is ready but no campus-specific overrides are live yet.
- **Remaining desktop cosmetic work:** You mentioned wanting 32 wallpaper photos (we have 16), plus login screen customization per campus. These can be added by dropping files into `roles/desktop/files/wallpapers/` and setting `desktop_login_background` in each site's group_vars.

## Scope Observations
- The plan held well — no scope drift or plan assumptions that proved wrong.
- The `$ANSIBLE_ROLES` env var not being set locally was a minor friction point for validation. Consider setting `roles_path = ./roles` in `ansible.cfg` instead of relying on the environment variable.
- The `desktop-22.04` role had significantly more modernization than expected (WhiteSur theme, VSCode, Blender/Inkscape/Kdenlive, handlers for pulseaudio/lightdm). All of this landed cleanly in the unified role.

## Recommended Next Session Starting Point
- Fix `host_vars/srv-gw` tab character
- Add remaining 16 wallpaper images (to reach 32 total)
- Set per-campus login backgrounds in group_vars (dvbs, dvgs, drbu)
- Consider Phase 3 from the original refactor plan: decompose the unified `common` role into focused function-roles
- Consider Phase 5: variable namespacing and argument_specs
