-- test_ldap_dismissal — read or set sudhanixWelcomeDismissed on any user.
-- Useful for QA-ing the welcome panel against a known LDAP state without
-- having to log in as that user.
--
-- Reads use the existing self:ldap_search anonymous-bind path. Writes shell
-- out to ldapmodify with the operator's own cached PAM token; the operator
-- must be in `it` (LDAP ACL gate) and must have an active session token.

local FLAG_ATTR = "sudhanixWelcomeDismissed"
local USER_OC = "sudhanixUser"

local function ldif_set_true(target_dn)
  return string.format([[dn: %s
changetype: modify
add: objectClass
objectClass: %s
-
replace: %s
%s: TRUE
]], target_dn, USER_OC, FLAG_ATTR, FLAG_ATTR)
end

local function ldif_clear(target_dn)
  return string.format([[dn: %s
changetype: modify
delete: %s
]], target_dn, FLAG_ATTR)
end

-- ---------------------------------------------------------------------------

local TOOL = {}

TOOL.id = "test-ldap-dismissal"
TOOL.label = "LDAP dismissal flag"
TOOL.category = "Testing"
TOOL.icon = "view-list"
TOOL.description = "Read or set sudhanixWelcomeDismissed on any user's LDAP entry."
TOOL.required_groups = { "it" }
TOOL.order = 40

function TOOL:_target_dn(uid)
  local cfg = self:config("ldap")
  local people = cfg.people_ou or "ou=People,dc=cttb"
  return string.format("uid=%s,%s", self:ldap_escape(uid), people)
end

function TOOL:_modify(target_dn, ldif)
  local cfg = self:config("ldap")
  local op_dn = self:my_ldap_dn()
  local op_uid = (self:run({ "id", "-u", self.user }, { timeout = 3 }).stdout or "")
                   :gsub("%s+$", "")
  local token = "/run/sudhanix-tokens/" .. op_uid .. ".tok"

  return self:run(
    { "ldapmodify", "-x", "-ZZ",
      "-H", cfg.uri or "ldap://ldap-srv.cttb",
      "-D", op_dn, "-y", token, "-c" },
    { input = ldif, timeout = 8 }
  )
end

function TOOL:action_get(fields)
  local uid = fields.uid
  if not uid or uid == "" then
    return { ok = false, title = "uid required" }
  end

  local target_dn = self:_target_dn(uid)
  local records = self:ldap_search(
    "(objectClass=*)",
    { FLAG_ATTR, "objectClass" },
    target_dn
  )

  if #records == 0 then
    return { ok = false, title = "No entry: " .. target_dn }
  end

  local rec = records[1]
  local dismissed = (rec[FLAG_ATTR] and rec[FLAG_ATTR][1]) or "(unset)"
  local ocs = table.concat(rec.objectClass or {}, ", ")

  return {
    ok = true,
    title = string.format("%s: %s = %s", uid, FLAG_ATTR, dismissed),
    body = "objectClass: " .. ocs,
    details = string.format("dn: %s\n%s: %s\nobjectClass: %s",
                             target_dn, FLAG_ATTR, dismissed, ocs),
  }
end

function TOOL:action_set_true(fields)
  if not fields.uid or fields.uid == "" then
    return { ok = false, title = "uid required" }
  end
  local target_dn = self:_target_dn(fields.uid)
  local r = self:_modify(target_dn, ldif_set_true(target_dn))
  return {
    ok = r.ok,
    title = r.ok and ("Set TRUE on " .. fields.uid) or "ldapmodify failed",
    body = (r.stdout ~= "" and r.stdout) or r.stderr,
    details = string.format("dn: %s\nrc: %d", target_dn, r.returncode),
  }
end

function TOOL:action_clear(fields)
  if not fields.uid or fields.uid == "" then
    return { ok = false, title = "uid required" }
  end
  local target_dn = self:_target_dn(fields.uid)
  local r = self:_modify(target_dn, ldif_clear(target_dn))
  return {
    ok = r.ok,
    title = r.ok and ("Cleared on " .. fields.uid) or "ldapmodify failed",
    body = (r.stdout ~= "" and r.stdout) or r.stderr,
    details = string.format("dn: %s\nrc: %d", target_dn, r.returncode),
  }
end

TOOL.actions = {
  {
    name = "get",
    label = "Read flag",
    description = "Anonymous LDAP search for the current value (and objectClass list).",
    button_label = "Read",
    fields = {
      { name = "uid", label = "uid", placeholder = "kit.chong" },
    },
    runner = TOOL.action_get,
  },
  {
    name = "set_true",
    label = "Set flag to TRUE",
    description = "Adds sudhanixUser objectClass if missing and sets the flag.",
    button_label = "Set TRUE",
    fields = {
      { name = "uid", label = "uid", placeholder = "kit.chong" },
    },
    runner = TOOL.action_set_true,
  },
  {
    name = "clear",
    label = "Clear flag",
    description = "Deletes sudhanixWelcomeDismissed (idempotent if already absent).",
    button_label = "Clear",
    fields = {
      { name = "uid", label = "uid", placeholder = "kit.chong" },
    },
    runner = TOOL.action_clear,
  },
}

registry.register(TOOL)
