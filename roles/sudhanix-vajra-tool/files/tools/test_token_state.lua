-- test_token_state — show /run/sudhanix-tokens/<uid>.tok metadata and the
-- recent cache-log activity. Token contents are NEVER displayed.

local function uid_for(ctx, user)
  local r = ctx:run({ "id", "-u", user }, { timeout = 3 })
  if not r.ok then return nil end
  return (r.stdout or ""):gsub("%s+$", "")
end

local function token_path_for(ctx, user)
  local uid = uid_for(ctx, user)
  if not uid or uid == "" then return nil end
  return "/run/sudhanix-tokens/" .. uid .. ".tok", uid
end

return {
  id = "test-token-state",
  label = "PAM token state",
  category = "Testing",
  icon = "preferences-system-privacy",
  description = "Inspect /run/sudhanix-tokens/<uid>.tok metadata and the cache-log tail "
             .. "(token contents never shown).",
  required_groups = { "it" },
  order = 20,

  actions = {
    {
      name = "inspect",
      label = "Inspect token + log",
      description = "Read metadata of /run/sudhanix-tokens/<uid>.tok and tail the cache log.",
      button_label = "Inspect",
      fields = {
        { name = "user", label = "user", placeholder = "(defaults to current)" },
      },
      runner = function(ctx, fields)
        local user = (fields.user ~= "" and fields.user) or ctx.user
        local path, uid = token_path_for(ctx, user)
        if not path then
          return { ok = false, title = "Unknown user: " .. user }
        end

        local stat = ctx:run_privileged(
          { "stat", "--format", "%n size=%s mode=%a owner=%U:%G mtime=%y", path },
          { timeout = 4 }
        )
        local log_tail = ctx:run_privileged(
          { "grep", "-E", string.format("PAM_USER=%s|/run/sudhanix-tokens/%s.tok", user, uid),
            "/var/log/sudhanix-pam-cache.log" },
          { timeout = 4 }
        )

        local present = stat.ok
        local body
        if present then
          body = "Token PRESENT.\n" .. (stat.stdout or "")
        else
          body = "Token ABSENT.\n" .. (stat.stderr or "")
        end

        return {
          ok = true,
          title = present and ("Token cached for " .. user) or ("No token for " .. user),
          body = body,
          details = string.format(
            "=== stat %s ===\n%s\n%s\n\n=== cache-log entries for uid=%s ===\n%s",
            path,
            stat.stdout or "",
            stat.stderr or "",
            uid,
            (log_tail.ok and log_tail.stdout) or log_tail.stderr or ""
          ),
        }
      end,
    },

    {
      name = "clear",
      label = "Clear my token",
      description = "Removes /run/sudhanix-tokens/<uid>.tok via privileged exec.",
      button_label = "Clear",
      runner = function(ctx, _)
        local path, uid = token_path_for(ctx, ctx.user)
        if not path then
          return { ok = false, title = "Cannot resolve uid for " .. ctx.user }
        end
        local r = ctx:run_privileged({ "rm", "-f", path }, { timeout = 4 })
        return {
          ok = r.ok,
          title = r.ok and ("Cleared " .. path) or ("Clear failed: " .. path),
          body = r.ok
            and string.format("Token for uid=%s removed. Next graphical login will rewrite.", uid)
            or  (r.stderr ~= "" and r.stderr) or r.stdout,
        }
      end,
    },
  },
}
