-- welcome_reset — clear the LDAP sudhanixWelcomeDismissed flag for the current user.
--
-- The Rust port has no PAM-token integration, so the user types their LDAP
-- password to authenticate the modify (same pattern as password_reset).

local WELCOME_FLAG_ATTR = "sudhanixWelcomeDismissed"

local function trim(s)
  return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function ldap_uri()
  local cfg = ctx:config("ldap")
  if type(cfg) == "table" and cfg.uri and cfg.uri ~= "" then
    return cfg.uri
  end
  return "ldap://ldap-srv.cttb"
end

local function people_ou()
  local cfg = ctx:config("ldap")
  if type(cfg) == "table" and cfg.people_ou and cfg.people_ou ~= "" then
    return cfg.people_ou
  end
  return "ou=People,dc=cttb"
end

-- ---------------------------------------------------------------------------

local TOOL = {}

TOOL.id = "welcome-reset"
TOOL.label = "Reset Welcome Dismissal"
TOOL.category = "Identity"
TOOL.icon = "view-refresh"
TOOL.description = "Clear the LDAP attribute so the welcome panel reappears at next login."
TOOL.required_groups = { "it", "sudo", "wheel", "admin" }
TOOL.order = 40

function TOOL:status_flag()
  local records = self:ldap_search(
    string.format("(uid=%s)", self:ldap_escape(self.user)),
    { WELCOME_FLAG_ATTR },
    people_ou()
  )
  if not records or #records == 0 then return "(no LDAP entry)" end
  local v = records[1][WELCOME_FLAG_ATTR]
  if v and v[1] then return v[1] end
  return "(unset)"
end

function TOOL:action_reset(fields)
  local pw = fields.password or ""
  if pw == "" then
    return { ok = false, title = "Password is required" }
  end
  local ldif = string.format(
    "dn: %s\nchangetype: modify\ndelete: %s\n",
    self:my_ldap_dn(),
    WELCOME_FLAG_ATTR
  )
  local uri = ldap_uri()
  local argv = { "ldapmodify", "-x" }
  -- Campus OpenLDAP enforces ssf>=128, so cleartext binds on ldap://
  -- are refused with "Confidentiality required (13)". Mirror the
  -- ldap_search StartTLS pattern: -ZZ for ldap://, untouched for ldaps://.
  if uri:sub(1, 7) == "ldap://" then
    argv[#argv + 1] = "-ZZ"
  end
  argv[#argv + 1] = "-H"; argv[#argv + 1] = uri
  argv[#argv + 1] = "-D"; argv[#argv + 1] = self:my_ldap_dn()
  argv[#argv + 1] = "-w"; argv[#argv + 1] = pw
  local r = self:run(argv, { input = ldif, timeout = 15 })
  if r.returncode ~= 0 then
    local stderr = r.stderr or ""
    -- "No such attribute" / rc 16 → already cleared.
    if stderr:find("No such attribute", 1, true) or r.returncode == 16 then
      return { ok = true, title = "Already reset", body = "Flag was not set." }
    end
    return {
      ok = false,
      title = "ldapmodify failed",
      details = stderr ~= "" and stderr or r.stdout,
    }
  end
  return {
    ok = true,
    title = "Welcome dismissal cleared",
    body = "Log out and back in to see the panel.",
  }
end

TOOL.statuses = {
  { name = "flag", label = "Current dismissal flag", order = 10, runner = TOOL.status_flag },
}

TOOL.actions = {
  {
    name = "reset",
    label = "Reset welcome dismissal",
    description = "Removes the LDAP attribute so the panel pops on your next login.",
    confirm = "Clear the welcome dismissal flag for this account?",
    button_label = "Reset",
    fields = {
      {
        name = "password",
        label = "Your LDAP password",
        kind = "password",
        help_text = "Authenticates the modify as you. Same password you log in with.",
      },
    },
    runner = TOOL.action_reset,
  },
}

registry.register(TOOL)
