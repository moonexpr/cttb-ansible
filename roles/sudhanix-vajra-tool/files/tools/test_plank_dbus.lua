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

local function parse_uri_list(s)
  -- gdbus prints tuples like: (['file:///a', 'file:///b'],)
  -- A trash entry can also appear as 'trash://'.
  local uris = {}
  for u in (s or ""):gmatch("(%a+://[^'\"%s,]+)") do
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

-- ---------------------------------------------------------------------------

local TOOL = {}

TOOL.id = "test-plank-dbus"
TOOL.label = "Plank DBus"
TOOL.category = "Testing"
TOOL.icon = "preferences-system-symbolic"
TOOL.description = "Inspect and mutate Plank's persistent dock items via its "
                .. "session-bus API (net.launchpad.plank.Items). Useful when "
                .. "the welcome customizer isn't producing the expected dock."
TOOL.required_groups = { "it" }
TOOL.order = 50

function TOOL:_gdbus_call(method, args)
  local argv = {
    "gdbus", "call", "--session",
    "--dest", DEST,
    "--object-path", OBJ,
    "--method", IFACE .. "." .. method,
  }
  for _, a in ipairs(args or {}) do argv[#argv + 1] = a end
  return self:run(argv, { timeout = 5 })
end

function TOOL:_plank_running()
  local r = self:run({
    "gdbus", "call", "--session",
    "--dest", "org.freedesktop.DBus",
    "--object-path", "/org/freedesktop/DBus",
    "--method", "org.freedesktop.DBus.NameHasOwner",
    DEST,
  }, { timeout = 3 })
  return r.ok and (r.stdout or ""):find("true", 1, true) ~= nil
end

function TOOL:status_plank()
  return self:_plank_running() and "running" or "(not on session bus)"
end

function TOOL:action_list_persistent()
  if not self:_plank_running() then
    return {
      ok = false,
      title = "Plank is not on the session bus",
      body = "No owner for " .. DEST .. ". Plank may be crashed or not yet "
          .. "started. Re-launch via the app menu, or wait for the XDG "
          .. "autostart entry to fire.",
    }
  end
  local r = self:_gdbus_call("GetPersistentApplications", {})
  if not r.ok then
    return {
      ok = false,
      title = "GetPersistentApplications failed",
      body = string.format("rc=%d\nstderr: %s", r.returncode, r.stderr),
    }
  end
  local uris = parse_uri_list(r.stdout)
  local cr = self:_gdbus_call("GetCount", {})
  local count_str = cr.ok and (cr.stdout or ""):gsub("[%s%(%),]", "") or "?"
  return {
    ok = true,
    title = string.format("Plank reports %d persistent item(s) (GetCount=%s)",
                          #uris, count_str),
    body = fmt_list(uris),
    details = "raw stdout:\n" .. r.stdout,
  }
end

function TOOL:action_add(fields)
  local uri = fields.uri or ""
  if uri == "" then
    return { ok = false, title = "URI required",
             body = "Example: file:///usr/share/applications/thunar.desktop" }
  end
  if not self:_plank_running() then
    return { ok = false, title = "Plank is not on the session bus",
             body = "Start plank first; the Add call needs a live instance." }
  end
  local r = self:_gdbus_call("Add", { uri })
  return {
    ok = r.ok,
    title = r.ok and ("Add issued: " .. uri) or "Add failed",
    body = string.format("rc=%d\n%s", r.returncode,
                          (r.ok and r.stdout) or r.stderr),
  }
end

function TOOL:action_remove(fields)
  local uri = fields.uri or ""
  if uri == "" then
    return { ok = false, title = "URI required",
             body = "Pick one from the List action's output." }
  end
  if not self:_plank_running() then
    return { ok = false, title = "Plank is not on the session bus",
             body = "Start plank first; Remove needs a live instance." }
  end
  local r = self:_gdbus_call("Remove", { uri })
  return {
    ok = r.ok,
    title = r.ok and ("Remove issued: " .. uri) or "Remove failed",
    body = string.format("rc=%d\n%s", r.returncode,
                          (r.ok and r.stdout) or r.stderr),
  }
end

function TOOL:action_introspect()
  local r = self:run({
    "gdbus", "introspect", "--session",
    "--dest", DEST, "--object-path", OBJ,
  }, { timeout = 5 })
  return {
    ok = r.ok,
    title = r.ok and "Plank /dock1 interfaces" or "Introspect failed",
    body = r.ok and r.stdout or r.stderr,
  }
end

TOOL.statuses = {
  { name = "plank", label = "Plank session-bus presence", order = 10,
    runner = TOOL.status_plank },
}

TOOL.actions = {
  { name = "list_persistent",
    label = "List persistent items",
    description = "Calls GetPersistentApplications; reports plank presence + URI list.",
    button_label = "List",
    runner = TOOL.action_list_persistent,
  },
  { name = "add",
    label = "Add URI",
    description = "Calls Items.Add(uri). Plank creates the .dockitem file and persists to dconf.",
    button_label = "Add",
    fields = {
      { name = "uri", label = "URI",
        placeholder = "file:///usr/share/applications/thunar.desktop" },
    },
    runner = TOOL.action_add,
  },
  { name = "remove",
    label = "Remove URI",
    description = "Calls Items.Remove(uri). Plank deletes the .dockitem file.",
    button_label = "Remove",
    fields = {
      { name = "uri", label = "URI",
        placeholder = "file:///usr/share/applications/thunar.desktop" },
    },
    runner = TOOL.action_remove,
  },
  { name = "introspect",
    label = "Introspect interface",
    description = "Calls org.freedesktop.DBus.Introspectable.Introspect on /net/launchpad/plank/dock1.",
    button_label = "Introspect",
    runner = TOOL.action_introspect,
  },
}

registry.register(TOOL)
