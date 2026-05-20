-- test_welcome_preview — preview the Sudhanix welcome window and reset
-- the per-user dismissal flag in LDAP.
--
-- "Show welcome window" assumes /usr/local/bin/sudhanix-welcome honors
-- $SUDHANIX_WELCOME_FORCE=1 to bypass the dismissal-flag short-circuit.

local function dismissal_ldif(user_dn)
  return string.format([[dn: %s
changetype: modify
delete: sudhanixWelcomeDismissed
]], user_dn)
end

-- ---------------------------------------------------------------------------

local TOOL = {}

TOOL.id = "test-welcome-preview"
TOOL.label = "Welcome panel preview"
TOOL.category = "Testing"
TOOL.icon = "preferences-desktop-display"
TOOL.description = "Open the Sudhanix welcome panel on demand and reset the "
                .. "per-user dismissal flag in LDAP."
TOOL.required_groups = { "it" }
TOOL.order = 30

function TOOL:_token_path()
  local uid = (self:run({ "id", "-u", self.user }, { timeout = 3 }).stdout or "")
                :gsub("%s+$", "")
  if uid == "" then return nil end
  return "/run/sudhanix-tokens/" .. uid .. ".tok"
end

function TOOL:_reset_dismissal()
  local cfg = self:config("ldap")
  local user_dn = self:my_ldap_dn()
  if not user_dn or user_dn == "" then
    return nil, "Cannot resolve LDAP DN for " .. self.user
  end
  local token = self:_token_path()
  if not token then return nil, "Cannot resolve uid for " .. self.user end

  local r = self:run(
    { "ldapmodify", "-x", "-ZZ",
      "-H", cfg.uri or "ldap://ldap-srv.cttb",
      "-D", user_dn,
      "-y", token,
      "-c" },                       -- continue on error (e.g. attr already absent)
    { input = dismissal_ldif(user_dn), timeout = 8 }
  )
  return r, nil
end

function TOOL:action_show()
  -- self:spawn returns nil on success (Rust Ok(()) → Lua nil) and
  -- raises a Lua error on failure. Use pcall to distinguish.
  local ok, err = pcall(function()
    self:spawn({ "env", "SUDHANIX_WELCOME_FORCE=1",
                 "/usr/local/bin/sudhanix-welcome" })
  end)
  if ok then
    return {
      ok = true,
      title = "Welcome window spawned",
      body = "If the dismissal flag is set on your LDAP entry and "
          .. "the welcome script does not yet honor SUDHANIX_WELCOME_FORCE, "
          .. "the window will exit silently. Use the 'Reset dismissal' "
          .. "action to clear the flag first.",
    }
  end
  return { ok = false, title = "Spawn failed", body = tostring(err) }
end

function TOOL:action_reset_flag()
  local r, err = self:_reset_dismissal()
  if not r then return { ok = false, title = err } end

  local msg = r.stdout
  if r.stderr ~= "" then msg = msg .. "\n" .. r.stderr end

  return {
    ok = r.ok,
    title = r.ok and "Dismissal flag cleared" or "ldapmodify failed",
    body  = (msg ~= "" and msg) or "(no output)",
    details = string.format("rc: %d", r.returncode),
  }
end

function TOOL:action_show_after_reset()
  local r, err = self:_reset_dismissal()
  if not r then return { ok = false, title = err } end

  self:spawn({ "env", "SUDHANIX_WELCOME_FORCE=1",
               "/usr/local/bin/sudhanix-welcome" })

  return {
    ok = r.ok,
    title = r.ok and "Reset + spawned" or "Reset failed (window not spawned)",
    body  = string.format("ldapmodify rc=%d\n%s\n%s",
                          r.returncode, r.stdout, r.stderr),
  }
end

TOOL.actions = {
  {
    name = "show",
    label = "Show welcome window",
    description = "Spawns /usr/local/bin/sudhanix-welcome with SUDHANIX_WELCOME_FORCE=1.",
    button_label = "Show",
    runner = TOOL.action_show,
  },
  {
    name = "reset_flag",
    label = "Reset dismissal flag",
    description = "Deletes sudhanixWelcomeDismissed from your LDAP entry.",
    button_label = "Reset",
    runner = TOOL.action_reset_flag,
  },
  {
    name = "show_after_reset",
    label = "Reset + show",
    description = "Resets the dismissal flag, then opens the welcome window.",
    button_label = "Reset + show",
    runner = TOOL.action_show_after_reset,
  },
}

registry.register(TOOL)
