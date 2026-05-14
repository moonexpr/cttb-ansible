-- super_key.lua — standalone diagnostic for the Super-key shortcut
-- family on Sudhanix 26.
--
-- Run as the logged-in user, in a desktop session (so xfconfd is up):
--
--   vajra lua /usr/local/share/sudhanix/diag/super_key.lua
--
-- Or over SSH from the operator's laptop:
--
--   ssh administrator@<host> 'bash -lc "vajra lua /usr/local/share/sudhanix/diag/super_key.lua"'
--
-- The bash -lc form is important: a non-login SSH shell has empty
-- XDG_DATA_DIRS / DISPLAY / XDG_RUNTIME_DIR and the xfconfd query
-- can fall through to defaults instead of the user's live session.
--
-- Covers gh-61 (Super+L lock) and gh-63 (Super-key app menu toggle):
-- captures whether the system kb-shortcut template is current, whether
-- the per-user xfconf cache has diverged, whether the target binaries
-- exist on PATH, and whether running them by hand succeeds.

local SYSTEM_XFCONF  = "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
local USER_XFCONF    = ctx.home .. "/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

local EXPECTED = {
  ["/commands/custom/Super_L"]   = "xfce4-popup-whiskermenu",    -- gh-63
  ["/commands/custom/<Super>l"]  = "xflock4",                    -- gh-61
}

local function trim(s) return (s or ""):gsub("%s+$", "") end

local function file_exists(path)
  return ctx:run({"test", "-e", path}).rc == 0
end

local function xfconf_get(channel, prop)
  local r = ctx:run({"xfconf-query", "-c", channel, "-p", prop})
  return (r.rc == 0) and trim(r.stdout) or "<not set>"
end

local function which(bin)
  local r = ctx:run({"which", bin})
  return (r.rc == 0) and trim(r.stdout) or nil
end

local function grep_template(path, key)
  if not file_exists(path) then return nil end
  -- xfconf XML stores < as &lt; and > as &gt;.
  local literal = key:gsub("<", "&lt;"):gsub(">", "&gt;")
  local r = ctx:run({"grep", "-F", string.format([[name="%s"]], literal), path})
  return (r.rc == 0) and trim(r.stdout) or nil
end

print("=== environment (matters: live xfconfd needs DISPLAY+DBUS) ===")
print(string.format("  user        : %s (uid=%s)", ctx.user, ctx.uid))
print(string.format("  HOME        : %s", ctx.home))
print(string.format("  DISPLAY     : %s", os.getenv("DISPLAY")     or "<unset>"))
print(string.format("  XDG_DATA_DIRS: %s", (os.getenv("XDG_DATA_DIRS") or "<unset>"):sub(1, 100)))
print(string.format("  XDG_RUNTIME_DIR: %s", os.getenv("XDG_RUNTIME_DIR") or "<unset>"))
print(string.format("  xfconfd running: %s",
  ctx:run({"pgrep", "-u", ctx.user, "xfconfd"}).rc == 0 and "yes" or "no"))

print()
print("=== system template (role-deployed at /etc/xdg/...) ===")
for key, _ in pairs(EXPECTED) do
  local line = grep_template(SYSTEM_XFCONF, key)
  print(string.format("  %-30s : %s", key, line or "<not present in template>"))
end

print()
print("=== per-user xfconf cache (this is what xfconfd actually reads) ===")
if file_exists(USER_XFCONF) then
  print("  " .. USER_XFCONF .. " : present (overrides system defaults)")
  for key, _ in pairs(EXPECTED) do
    local line = grep_template(USER_XFCONF, key)
    print(string.format("  %-30s : %s", key, line or "<not in user file — falls through to system>"))
  end
else
  print("  " .. USER_XFCONF .. " : absent (xfconfd reads from system template)")
end

print()
print("=== live xfconfd (the values keypresses actually dispatch) ===")
for key, want in pairs(EXPECTED) do
  local got = xfconf_get("xfce4-keyboard-shortcuts", key)
  local verdict
  if got == want then
    verdict = "OK"
  elseif got == "<not set>" then
    verdict = "BROKEN (binding missing — keypress will do nothing)"
  else
    verdict = string.format("STALE (got %s, want %s)", got, want)
  end
  print(string.format("  %-30s -> %s :: %s", key, got, verdict))
end

print()
print("=== target binaries on PATH ===")
for _, bin in ipairs({"xfce4-popup-whiskermenu", "xflock4",
                     "light-locker-command", "sudhanix-toggle-appmenu"}) do
  local p = which(bin)
  print(string.format("  %-30s -> %s", bin, p or "MISSING"))
end

print()
print("=== ad-hoc invocation: xflock4 (fires the screen locker) ===")
print("  NOTE: this would lock the screen if it works. Skipping by default.")
print("  To exercise: vajra lua -e 'print(ctx:run({\"xflock4\"}).rc)'")

print()
print("=== ad-hoc invocation: xfce4-popup-whiskermenu (toggles menu) ===")
print("  NOTE: opens/closes the menu visually. Skipping by default.")
print("  To exercise: vajra lua -e 'print(ctx:run({\"xfce4-popup-whiskermenu\"}).rc)'")

print()
print("=== summary verdict ===")
local sys_super_l   = grep_template(SYSTEM_XFCONF, "/commands/custom/Super_L") or ""
local sys_super_lower_l = grep_template(SYSTEM_XFCONF, "/commands/custom/<Super>l") or ""
local user_present = file_exists(USER_XFCONF)
local live_super_l   = xfconf_get("xfce4-keyboard-shortcuts", "/commands/custom/Super_L")
local live_super_lower_l = xfconf_get("xfce4-keyboard-shortcuts", "/commands/custom/<Super>l")

if sys_super_l:find("xfce4%-popup%-whiskermenu") and sys_super_lower_l:find("xflock4") then
  print("  [✓] System template carries gh-61 + gh-63 fixes.")
else
  print("  [✗] System template missing one or both fixes — redeploy from")
  print("      the integration branch:")
  print("        ansible-playbook plays/install-sudhanix-cslabs.yml \\")
  print("            --limit dvgs-testmachine.cttb --tags sudhanix-ux --diff")
end

if user_present and live_super_l ~= EXPECTED["/commands/custom/Super_L"] then
  print("  [!] Per-user xfconf cache is overriding system defaults.")
  print("      To force re-seed from the (fixed) system template:")
  print("        rm " .. USER_XFCONF)
  print("        xfce4-panel --restart   # or log out/in")
end

if live_super_l == EXPECTED["/commands/custom/Super_L"] and
   live_super_lower_l == EXPECTED["/commands/custom/<Super>l"] then
  print("  [✓] Live xfconfd reports the expected bindings.")
  print("      If the keys still don't fire, escalate to xfsettingsd /")
  print("      the keyboard-grab path — see #36's analysis.")
end
