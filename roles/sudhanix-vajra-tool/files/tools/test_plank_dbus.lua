-- test_plank_dbus — poke at the running Plank instance over its session-bus
-- API, independent of the welcome panel.
--
-- Counterpart to sudhanix-welcome's PlankDock.replace_items, which speaks
-- net.launchpad.plank.Items.{Add,Remove,GetPersistentApplications} on
-- /net/launchpad/plank/dock1. This tool exposes the same primitives as
-- one-off actions so an operator can verify the bus path, watch live
-- changes, and reproduce dock state without bringing up the welcome panel.

local DEST = "net.launchpad.plank"
local OBJ  = "/net/launchpad/plank/dock1"
local IFACE = "net.launchpad.plank.Items"

local function gdbus_call(ctx, method, args)
  -- args is a (possibly empty) list of positional argv strings.
  local argv = {
    "gdbus", "call", "--session",
    "--dest", DEST,
    "--object-path", OBJ,
    "--method", IFACE .. "." .. method,
  }
  for _, a in ipairs(args or {}) do argv[#argv + 1] = a end
  return ctx:run(argv, { timeout = 5 })
end

local function parse_uri_list(s)
  -- gdbus prints tuples like: (['file:///a', 'file:///b'],)
  -- A trash entry can also appear as 'trash://'.
  local uris = {}
  for u in (s or ""):gmatch("([%a]+://[^'\"%s,]+)") do
    uris[#uris + 1] = u
  end
  return uris
end

local function fmt_list(uris)
  if #uris == 0 then return "(empty)" end
  local lines = {}
  for i, u in ipairs(uris) do
    lines[#lines + 1] = string.format("  %2d  %s", i, u)
  end
  return table.concat(lines, "\n")
end

local function plank_running(ctx)
  local r = ctx:run({
    "gdbus", "call", "--session",
    "--dest", "org.freedesktop.DBus",
    "--object-path", "/org/freedesktop/DBus",
    "--method", "org.freedesktop.DBus.NameHasOwner",
    DEST,
  }, { timeout = 3 })
  return r.ok and (r.stdout or ""):find("true", 1, true) ~= nil
end

return {
  id = "test-plank-dbus",
  label = "Plank DBus",
  category = "Testing",
  icon = "preferences-system-symbolic",
  description = "Inspect and mutate Plank's persistent dock items via its "
             .. "session-bus API (net.launchpad.plank.Items). Useful when "
             .. "the welcome customizer isn't producing the expected dock.",
  required_groups = { "it" },
  order = 30,

  actions = {
    {
      name = "list_persistent",
      label = "List persistent items",
      description = "Calls GetPersistentApplications; reports plank presence + URI list.",
      button_label = "List",
      runner = function(ctx)
        if not plank_running(ctx) then
          return {
            ok = false,
            title = "Plank is not on the session bus",
            body = "No owner for " .. DEST .. ". Plank may be crashed or "
                .. "not yet started. Re-launch via the app menu, or wait "
                .. "for the XDG autostart entry to fire.",
          }
        end
        local r = gdbus_call(ctx, "GetPersistentApplications", {})
        if not r.ok then
          return {
            ok = false,
            title = "GetPersistentApplications failed",
            body = string.format("rc=%d\nstderr: %s", r.returncode, r.stderr),
          }
        end
        local uris = parse_uri_list(r.stdout)
        local cr = gdbus_call(ctx, "GetCount", {})
        local count_str = cr.ok and (cr.stdout or ""):gsub("[%s%(%),]", "") or "?"
        return {
          ok = true,
          title = string.format("Plank reports %d persistent item(s) (GetCount=%s)",
                                #uris, count_str),
          body = fmt_list(uris),
          details = "raw stdout:\n" .. r.stdout,
        }
      end,
    },

    {
      name = "add_uri",
      label = "Add URI",
      description = "Calls Items.Add(uri). Plank creates the .dockitem file and persists to dconf.",
      button_label = "Add",
      fields = {
        { name = "uri", label = "URI",
          placeholder = "file:///usr/share/applications/thunar.desktop" },
      },
      runner = function(ctx, fields)
        local uri = fields.uri or ""
        if uri == "" then
          return { ok = false, title = "URI required",
                   body = "Example: file:///usr/share/applications/thunar.desktop" }
        end
        if not plank_running(ctx) then
          return { ok = false, title = "Plank is not on the session bus",
                   body = "Start plank first; the Add call needs a live instance." }
        end
        local r = gdbus_call(ctx, "Add", { uri })
        return {
          ok = r.ok,
          title = r.ok and ("Add issued: " .. uri) or "Add failed",
          body = string.format("rc=%d\n%s",
                               r.returncode,
                               (r.ok and r.stdout) or r.stderr),
        }
      end,
    },

    {
      name = "remove_uri",
      label = "Remove URI",
      description = "Calls Items.Remove(uri). Plank deletes the .dockitem file.",
      button_label = "Remove",
      fields = {
        { name = "uri", label = "URI",
          placeholder = "file:///usr/share/applications/thunar.desktop" },
      },
      runner = function(ctx, fields)
        local uri = fields.uri or ""
        if uri == "" then
          return { ok = false, title = "URI required",
                   body = "Pick one from the List action's output." }
        end
        if not plank_running(ctx) then
          return { ok = false, title = "Plank is not on the session bus",
                   body = "Start plank first; Remove needs a live instance." }
        end
        local r = gdbus_call(ctx, "Remove", { uri })
        return {
          ok = r.ok,
          title = r.ok and ("Remove issued: " .. uri) or "Remove failed",
          body = string.format("rc=%d\n%s",
                               r.returncode,
                               (r.ok and r.stdout) or r.stderr),
        }
      end,
    },

    {
      name = "introspect",
      label = "Introspect interface",
      description = "Calls org.freedesktop.DBus.Introspectable.Introspect on /net/launchpad/plank/dock1.",
      button_label = "Introspect",
      runner = function(ctx)
        local r = ctx:run({
          "gdbus", "introspect", "--session",
          "--dest", DEST, "--object-path", OBJ,
        }, { timeout = 5 })
        return {
          ok = r.ok,
          title = r.ok and "Plank /dock1 interfaces" or "Introspect failed",
          body = r.ok and r.stdout or r.stderr,
        }
      end,
    },
  },
}
