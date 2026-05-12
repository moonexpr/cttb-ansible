-- xfce_reset — quarantine XFCE config + re-run sudhanix-firstlogin bootstrap.
--
-- For "my desktop is weird" tickets where the user wants to start fresh
-- without losing their files. Files are moved into a timestamped quarantine
-- dir under $HOME so nothing is destroyed.

local CONFIG_PATHS = {
  ".config/xfce4",
  ".config/Thunar",
  ".config/plank",
  ".config/devilspie2",
  ".gtkrc-2.0",
  ".gtkrc-2.0.mine",
  ".cache/sessions",
}

local FIRSTLOGIN_BIN = "/usr/local/sbin/sudhanix-firstlogin"
local MARKER        = ".config/sudhanix/firstlogin-done"

local function trim(s)
  return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function exists(path)
  return ctx:run({ "test", "-e", path }, { timeout = 3 }).returncode == 0
end

local function is_file(path)
  return ctx:run({ "test", "-f", path }, { timeout = 3 }).returncode == 0
end

local function timestamp()
  return trim(ctx:run({ "date", "+%Y%m%d-%H%M%S" }, { timeout = 3 }).stdout)
end

-- ---------------------------------------------------------------------------

local TOOL = {}

TOOL.id = "xfce-reset"
TOOL.label = "Reset XFCE Config"
TOOL.category = "Hot Fixes"
TOOL.icon = "edit-undo"
TOOL.description = "Quarantine your XFCE config and re-bootstrap from /etc/skel + xfconf defaults."
TOOL.required_groups = { "it", "sudo", "wheel", "admin" }
TOOL.order = 20

function TOOL:action_reset()
  -- Refuse to quarantine if there's no rebuild path: without
  -- sudhanix-firstlogin to repopulate /etc/skel + xfconf defaults,
  -- the user lands in a broken D-Bus / xfconfd state at next login
  -- ("Unable to load a failsafe session"). Discovered the hard way
  -- on dvgs-testmachine 2026-05-07.
  if not is_file(FIRSTLOGIN_BIN) then
    return {
      ok = false,
      title = "Refusing to reset — bootstrap script missing",
      body = string.format(
        "%s does not exist on this host. Without it, your XFCE config would be moved aside but never replaced, leaving you unable to start a session.",
        FIRSTLOGIN_BIN
      ),
      details = "Install or restore the sudhanix-firstlogin script first, then retry.",
    }
  end

  local ts = timestamp()
  if ts == "" then ts = "now" end
  local qdir = string.format("%s/.sudhanix-quarantine-%s", self.home, ts)
  local mk = self:run({ "mkdir", "-p", qdir }, { timeout = 5 })
  if mk.returncode ~= 0 then
    return {
      ok = false,
      title = "Could not create quarantine dir",
      details = mk.stderr ~= "" and mk.stderr or mk.stdout,
    }
  end

  local moved = {}
  for _, rel in ipairs(CONFIG_PATHS) do
    local src = self.home .. "/" .. rel
    if exists(src) then
      local dst = qdir .. "/" .. rel:gsub("/", "__")
      local mv = self:run({ "mv", "--", src, dst }, { timeout = 10 })
      if mv.returncode == 0 then
        moved[#moved + 1] = string.format("%s -> %s", src, dst)
      else
        moved[#moved + 1] = string.format("%s FAILED (%s)", src, trim(mv.stderr))
      end
    end
  end

  local marker = self.home .. "/" .. MARKER
  if exists(marker) then
    self:run({ "rm", "-f", "--", marker }, { timeout = 3 })
  end

  -- Pre-flight already verified FIRSTLOGIN_BIN exists; run it.
  local r = self:run({ FIRSTLOGIN_BIN }, { timeout = 120 })
  local bootstrap = string.format(
    "=== ran %s (rc=%d) ===\n%s\n%s",
    FIRSTLOGIN_BIN, r.returncode, r.stdout, r.stderr
  )

  return {
    ok = true,
    title = string.format("Quarantined %d item(s) to %s", #moved, qdir),
    body = "Log out and back in for changes to take effect.",
    details = table.concat(moved, "\n") .. "\n\n" .. bootstrap,
  }
end

TOOL.actions = {
  {
    name = "reset",
    label = "Quarantine + re-bootstrap XFCE config",
    description = "Moves your existing xfce4/Thunar/plank config under ~/.sudhanix-quarantine-<ts>/ then re-runs the first-login script. Log out and back in afterwards.",
    confirm = "Quarantine your XFCE config and re-run first-login bootstrap?",
    button_label = "Reset",
    runner = TOOL.action_reset,
  },
}

registry.register(TOOL)
