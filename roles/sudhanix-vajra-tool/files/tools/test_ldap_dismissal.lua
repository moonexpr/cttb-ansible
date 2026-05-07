-- test_ldap_dismissal — read or set sudhanixWelcomeDismissed on any user.
-- Useful for QA-ing the welcome panel against a known LDAP state without
-- having to log in as that user.
--
-- Reads use the existing ctx:ldap_search anonymous-bind path. Writes shell
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

local function modify(ctx, target_dn, ldif)
  local cfg = ctx:config("ldap")
  local op_dn = ctx:my_ldap_dn()
  local uid = (ctx:run({ "id", "-u", ctx.user }, { timeout = 3 }).stdout or "")
                :gsub("%s+$", "")
  local token = "/run/sudhanix-tokens/" .. uid .. ".tok"

  return ctx:run(
    { "ldapmodify", "-x", "-ZZ",
      "-H", cfg.uri or "ldap://ldap-srv.cttb",
      "-D", op_dn, "-y", token, "-c" },
    { input = ldif, timeout = 8 }
  )
end

return {
  id = "test-ldap-dismissal",
  label = "LDAP dismissal flag",
  category = "Testing",
  icon = "view-list",
  description = "Read or set sudhanixWelcomeDismissed on any user's LDAP entry.",
  required_groups = { "it" },
  order = 40,

  actions = {
    {
      name = "get",
      label = "Read flag",
      description = "Anonymous LDAP search for the current value (and objectClass list).",
      button_label = "Read",
      fields = {
        { name = "uid", label = "uid", placeholder = "kit.chong" },
      },
      runner = function(ctx, fields)
        local uid = fields.uid
        if not uid or uid == "" then
          return { ok = false, title = "uid required" }
        end

        local cfg = ctx:config("ldap")
        local people = cfg.people_ou or "ou=People,dc=cttb"
        local target_dn = string.format("uid=%s,%s", ctx:ldap_escape(uid), people)

        local records = ctx:ldap_search(
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
      end,
    },

    {
      name = "set_true",
      label = "Set flag to TRUE",
      description = "Adds sudhanixUser objectClass if missing and sets the flag.",
      button_label = "Set TRUE",
      fields = {
        { name = "uid", label = "uid", placeholder = "kit.chong" },
      },
      runner = function(ctx, fields)
        if not fields.uid or fields.uid == "" then
          return { ok = false, title = "uid required" }
        end
        local cfg = ctx:config("ldap")
        local people = cfg.people_ou or "ou=People,dc=cttb"
        local target_dn = string.format("uid=%s,%s", ctx:ldap_escape(fields.uid), people)

        local r = modify(ctx, target_dn, ldif_set_true(target_dn))
        return {
          ok = r.ok,
          title = r.ok and "Set TRUE on " .. fields.uid or "ldapmodify failed",
          body = (r.stdout ~= "" and r.stdout) or r.stderr,
          details = string.format("dn: %s\nrc: %d", target_dn, r.returncode),
        }
      end,
    },

    {
      name = "clear",
      label = "Clear flag",
      description = "Deletes sudhanixWelcomeDismissed (idempotent if already absent).",
      button_label = "Clear",
      fields = {
        { name = "uid", label = "uid", placeholder = "kit.chong" },
      },
      runner = function(ctx, fields)
        if not fields.uid or fields.uid == "" then
          return { ok = false, title = "uid required" }
        end
        local cfg = ctx:config("ldap")
        local people = cfg.people_ou or "ou=People,dc=cttb"
        local target_dn = string.format("uid=%s,%s", ctx:ldap_escape(fields.uid), people)

        local r = modify(ctx, target_dn, ldif_clear(target_dn))
        return {
          ok = r.ok,
          title = r.ok and "Cleared on " .. fields.uid or "ldapmodify failed",
          body = (r.stdout ~= "" and r.stdout) or r.stderr,
          details = string.format("dn: %s\nrc: %d", target_dn, r.returncode),
        }
      end,
    },
  },
}
