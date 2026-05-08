-- theme — identify and switch the active GTK/icon/cursor/window/plank/wallpaper
-- theme on a Sudhanix host. Mirrors what the welcome panel's Customization
-- pane does, so a sysadmin can read or set the same state without driving
-- the welcome window. Read-only by default; theme switching is a separate
-- action with its own button.

-- GTK theme dir + icon theme dir for each mode. Names match what's actually
-- installed in /usr/share/themes/ and /usr/share/icons/: the WhiteSur GTK
-- package ships a base "WhiteSur" (light) plus "WhiteSur-Dark"; the icon
-- set ships lowercase "WhiteSur-light" / "WhiteSur-dark". Non-existent
-- names silently fall back to Adwaita.
local LIGHT_GTK,  LIGHT_ICONS  = "WhiteSur",      "WhiteSur-light"
local DARK_GTK,   DARK_ICONS   = "WhiteSur-Dark", "WhiteSur-dark"

local function trim(s)
  return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function or_else(s, fallback)
  if s and s ~= "" then return s end
  return fallback
end

local function xfconf_read(ctx, channel, prop)
  local r = ctx:run({ "xfconf-query", "-c", channel, "-p", prop },
    { timeout = 5 })
  if r.returncode ~= 0 then return "" end
  return trim(r.stdout)
end

local function dconf_read(ctx, key)
  local r = ctx:run({ "dconf", "read", key }, { timeout = 5 })
  if r.returncode ~= 0 then return "" end
  return trim(r.stdout)
end

local function xfconf_write(ctx, channel, prop, value)
  return ctx:run(
    { "xfconf-query", "-c", channel, "-p", prop, "-s", value },
    { timeout = 5 }
  )
end

-- xfce4-desktop tracks wallpaper per monitor + per workspace; pull the
-- last-image from the first connected monitor's workspace0 we find.
local function find_wallpaper(ctx)
  local r = ctx:run({ "xfconf-query", "-c", "xfce4-desktop", "-lv" },
    { timeout = 5 })
  if r.returncode ~= 0 then return "" end
  for line in r.stdout:gmatch("[^\n]+") do
    local prop, value = line:match("^(%S+)%s+(.+)$")
    if prop and prop:match("/last%-image$") then
      return trim(value)
    end
  end
  return ""
end

local function basename(path)
  return (path or ""):match("([^/]+)$") or ""
end

local function classify_theme(name)
  local lower = (name or ""):lower()
  if lower:find("light", 1, true) then return "light" end
  if lower:find("dark", 1, true) then return "dark" end
  return "neutral"
end

return {
  id = "theme",
  label = "Theme",
  category = "Sudhanix",
  icon = "preferences-desktop-theme",
  description = "Identify the active GTK / icon / window / dock / wallpaper theme; quick Light/Dark toggle.",
  required_groups = { "it", "sudo", "wheel", "admin" },
  order = 25,

  statuses = {
    {
      name = "gtk",
      label = "GTK theme",
      order = 10,
      runner = function(ctx)
        local v = xfconf_read(ctx, "xsettings", "/Net/ThemeName")
        return or_else(v, "(unset)")
      end,
    },
    {
      name = "mode",
      label = "Light / Dark",
      order = 15,
      runner = function(ctx)
        local v = xfconf_read(ctx, "xsettings", "/Net/ThemeName")
        local k = classify_theme(v)
        if k == "light" then return "Light" end
        if k == "dark"  then return "Dark"  end
        return "Neutral / mixed"
      end,
    },
    {
      name = "icons",
      label = "Icon theme",
      order = 20,
      runner = function(ctx)
        local v = xfconf_read(ctx, "xsettings", "/Net/IconThemeName")
        return or_else(v, "(unset)")
      end,
    },
    {
      name = "cursor",
      label = "Cursor theme",
      order = 30,
      runner = function(ctx)
        local v = xfconf_read(ctx, "xsettings", "/Gtk/CursorThemeName")
        return or_else(v, "(unset)")
      end,
    },
    {
      name = "xfwm",
      label = "Window decorations",
      order = 40,
      runner = function(ctx)
        local v = xfconf_read(ctx, "xfwm4", "/general/theme")
        return or_else(v, "(unset)")
      end,
    },
    {
      name = "plank",
      label = "Plank dock theme",
      order = 50,
      runner = function(ctx)
        local v = dconf_read(ctx, "/net/launchpad/plank/docks/dock1/theme")
        if v == "" then return "Default" end
        -- dconf wraps strings in single quotes
        return v:gsub("^'(.*)'$", "%1")
      end,
    },
    {
      name = "wallpaper",
      label = "Wallpaper",
      order = 60,
      runner = function(ctx)
        local p = find_wallpaper(ctx):gsub("^'(.*)'$", "%1")
        if p == "" then return "(unset)" end
        return basename(p)
      end,
    },
  },

  actions = {
    {
      name = "report",
      label = "Show full theme report",
      button_label = "Show",
      runner = function(ctx)
        local rows = {
          { "GTK theme",          xfconf_read(ctx, "xsettings", "/Net/ThemeName") },
          { "Icon theme",         xfconf_read(ctx, "xsettings", "/Net/IconThemeName") },
          { "Cursor theme",       xfconf_read(ctx, "xsettings", "/Gtk/CursorThemeName") },
          { "Window decorations", xfconf_read(ctx, "xfwm4",     "/general/theme") },
          { "Plank dock theme",   dconf_read(ctx,  "/net/launchpad/plank/docks/dock1/theme") },
          { "Plymouth theme",     trim(ctx:run({ "sh", "-c",
              "plymouth-set-default-theme 2>/dev/null || true" }, { timeout = 3 }).stdout) },
          { "Wallpaper",          find_wallpaper(ctx) },
        }
        local lines = {}
        for _, kv in ipairs(rows) do
          local k, v = kv[1], kv[2]
          if v == "" then v = "(unset)" end
          lines[#lines + 1] = string.format("%-22s %s", k .. ":", v)
        end
        return {
          ok = true,
          title = "Active theme",
          details = table.concat(lines, "\n"),
        }
      end,
    },

    {
      name = "switch_light",
      label = "Switch GTK + icons to Light (" .. LIGHT_GTK .. " / " .. LIGHT_ICONS .. ")",
      button_label = "Light",
      confirm = "Set GTK theme to " .. LIGHT_GTK .. " and icons to " .. LIGHT_ICONS .. "?",
      runner = function(ctx)
        local r1 = xfconf_write(ctx, "xsettings", "/Net/ThemeName",     LIGHT_GTK)
        local r2 = xfconf_write(ctx, "xsettings", "/Net/IconThemeName", LIGHT_ICONS)
        if r1.returncode ~= 0 or r2.returncode ~= 0 then
          return {
            ok = false,
            title = "Theme switch failed",
            details = trim(r1.stderr) .. "\n" .. trim(r2.stderr),
          }
        end
        return { ok = true, title = "Switched to " .. LIGHT_GTK .. " / " .. LIGHT_ICONS }
      end,
    },

    {
      name = "switch_dark",
      label = "Switch GTK + icons to Dark (" .. DARK_GTK .. " / " .. DARK_ICONS .. ")",
      button_label = "Dark",
      confirm = "Set GTK theme to " .. DARK_GTK .. " and icons to " .. DARK_ICONS .. "?",
      runner = function(ctx)
        local r1 = xfconf_write(ctx, "xsettings", "/Net/ThemeName",     DARK_GTK)
        local r2 = xfconf_write(ctx, "xsettings", "/Net/IconThemeName", DARK_ICONS)
        if r1.returncode ~= 0 or r2.returncode ~= 0 then
          return {
            ok = false,
            title = "Theme switch failed",
            details = trim(r1.stderr) .. "\n" .. trim(r2.stderr),
          }
        end
        return { ok = true, title = "Switched to " .. DARK_GTK .. " / " .. DARK_ICONS }
      end,
    },
  },
}
