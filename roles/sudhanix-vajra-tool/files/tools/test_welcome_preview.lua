-- test_welcome_preview — preview the Sudhanix welcome window and reset
-- the per-user dismissal flag in LDAP.
--
-- "Show welcome window" assumes /usr/local/bin/sudhanix-welcome honors
-- $SUDHANIX_WELCOME_FORCE=1 to bypass the dismissal-flag short-circuit.
-- Until that lands upstream, the spawn still works on never-dismissed
-- users (since dismissed=false → window pops by default).

local function dismissal_ldif(user_dn)
  -- Build an LDIF that deletes sudhanixWelcomeDismissed (and removes the
  -- aux objectClass if it's only there to carry the flag). Keep it simple:
  -- just remove the attribute. If aux objectClass remains, harmless.
  return string.format([[dn: %s
changetype: modify
delete: sudhanixWelcomeDismissed
]], user_dn)
end

return {
  id = "test-welcome-preview",
  label = "Welcome panel preview",
  category = "Testing",
  icon = "preferences-desktop-display",
  description = "Open the Sudhanix welcome panel on demand and reset the "
             .. "per-user dismissal flag in LDAP.",
  required_groups = { "it" },
  order = 30,

  actions = {
    {
      name = "show",
      label = "Show welcome window",
      description = "Spawns /usr/local/bin/sudhanix-welcome with SUDHANIX_WELCOME_FORCE=1.",
      button_label = "Show",
      runner = function(ctx, _)
        -- ctx:spawn returns nil on success (Rust Ok(()) → Lua nil) and
        -- raises a Lua error on failure. Use pcall to distinguish.
        local ok, err = pcall(function()
          ctx:spawn({ "env", "SUDHANIX_WELCOME_FORCE=1",
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
      end,
    },

    {
      name = "reset_flag",
      label = "Reset dismissal flag",
      description = "Deletes sudhanixWelcomeDismissed from your LDAP entry.",
      button_label = "Reset",
      runner = function(ctx, _)
        local cfg = ctx:config("ldap")
        local user_dn = ctx:my_ldap_dn()
        if not user_dn or user_dn == "" then
          return { ok = false, title = "Cannot resolve LDAP DN for " .. ctx.user }
        end

        -- Token-y bind via the cached PAM token — same path sudhanix-welcome
        -- uses. If no token, ldapmodify will reject; surface that clearly.
        local uid = (ctx:run({ "id", "-u", ctx.user }, { timeout = 3 }).stdout or "")
                      :gsub("%s+$", "")
        local token = "/run/sudhanix-tokens/" .. uid .. ".tok"

        local r = ctx:run(
          { "ldapmodify", "-x", "-ZZ",
            "-H", cfg.uri or "ldap://ldap-srv.cttb",
            "-D", user_dn,
            "-y", token,
            "-c" },                       -- continue on error (e.g. attr already absent)
          { input = dismissal_ldif(user_dn), timeout = 8 }
        )

        local msg = r.stdout
        if r.stderr ~= "" then msg = msg .. "\n" .. r.stderr end

        return {
          ok = r.ok,
          title = r.ok and "Dismissal flag cleared" or "ldapmodify failed",
          body  = (msg ~= "" and msg) or "(no output)",
          details = string.format("dn: %s\ntoken: %s\nrc: %d", user_dn, token, r.returncode),
        }
      end,
    },

    {
      name = "show_after_reset",
      label = "Reset + show",
      description = "Resets the dismissal flag, then opens the welcome window.",
      button_label = "Reset + show",
      runner = function(ctx, _)
        -- Re-use the reset_flag runner inline — Lua tools can't invoke each
        -- other directly, so we duplicate the small action here.
        local cfg = ctx:config("ldap")
        local user_dn = ctx:my_ldap_dn()
        local uid = (ctx:run({ "id", "-u", ctx.user }, { timeout = 3 }).stdout or "")
                      :gsub("%s+$", "")
        local token = "/run/sudhanix-tokens/" .. uid .. ".tok"

        local reset = ctx:run(
          { "ldapmodify", "-x", "-ZZ",
            "-H", cfg.uri or "ldap://ldap-srv.cttb",
            "-D", user_dn, "-y", token, "-c" },
          { input = dismissal_ldif(user_dn), timeout = 8 }
        )

        ctx:spawn({ "env", "SUDHANIX_WELCOME_FORCE=1",
                    "/usr/local/bin/sudhanix-welcome" })

        return {
          ok = reset.ok,
          title = reset.ok and "Reset + spawned" or "Reset failed (window not spawned)",
          body  = string.format("ldapmodify rc=%d\n%s\n%s",
                                reset.returncode, reset.stdout, reset.stderr),
        }
      end,
    },
  },
}
