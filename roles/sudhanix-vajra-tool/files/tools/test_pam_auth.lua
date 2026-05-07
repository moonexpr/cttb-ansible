-- test_pam_auth — drive pamtester against a PAM service from the GUI.
--
-- Local-seat counterpart to utils/run-pam-test (cttb-ansible#3) for IT staff
-- doing per-host sanity checks during a Sudhanix rollout. Same primitive:
-- pipe a password into `pamtester <service> <user> authenticate` and read
-- the side-effects (cache log, /run/sudhanix-tokens/).

local function tail_lines(s, n)
  local lines = {}
  for line in (s or ""):gmatch("([^\n]*)\n?") do
    lines[#lines + 1] = line
  end
  -- gmatch leaves a trailing empty for trailing newlines; trim it
  if lines[#lines] == "" then table.remove(lines) end
  if #lines <= n then return table.concat(lines, "\n") end
  return table.concat({ table.unpack(lines, #lines - n + 1) }, "\n")
end

local function pre_flight(ctx)
  if not ctx:has("pamtester") then
    return false,
           "pamtester not installed",
           "Add this host to [cttb_login_testbeds] in inventory and run:\n"
        .. "  ansible-playbook plays/login-testbed.yml --limit <host> --diff"
  end
  return true
end

return {
  id = "test-pam-auth",
  label = "PAM auth",
  category = "Testing",
  icon = "dialog-password",
  description = "Drive pamtester against the lightdm (or other) PAM stack to validate auth-phase hooks.",
  required_groups = { "it" },
  order = 10,

  actions = {
    {
      name = "drive_auth",
      label = "Run pamtester authenticate",
      description = "Pipes the password into pamtester via privileged exec; "
                 .. "then surfaces the cache log + token-dir state.",
      button_label = "Authenticate",
      fields = {
        { name = "service",  label = "service",  placeholder = "lightdm" },
        { name = "user",     label = "user",     placeholder = "john.chandara" },
        { name = "password", label = "password", placeholder = "••••••••", secret = true },
      },
      runner = function(ctx, fields)
        local ok, title, body = pre_flight(ctx)
        if not ok then return { ok = false, title = title, body = body } end

        local service = (fields.service ~= "" and fields.service) or "lightdm"
        local user    = (fields.user    ~= "" and fields.user)    or ctx.user
        local pw      = fields.password or ""
        if pw == "" then
          return { ok = false, title = "Empty password",
                   body = "PAM auth would short-circuit; refusing." }
        end

        local r = ctx:run_privileged(
          { "pamtester", service, user, "authenticate" },
          { input = pw .. "\n", timeout = 12 }
        )

        local log_tail = ctx:run_privileged(
          { "tail", "-n", "20", "/var/log/sudhanix-pam-cache.log" },
          { timeout = 4 }
        )
        local token_ls = ctx:run_privileged(
          { "ls", "-la", "/run/sudhanix-tokens/" },
          { timeout = 4 }
        )

        local body_lines = {
          string.format("pamtester rc=%d", r.returncode),
          (r.stdout ~= "" and r.stdout) or (r.stderr ~= "" and r.stderr) or "(no output)",
        }
        local details = string.format(
          "=== pamtester ===\nrc=%d\nstdout: %s\nstderr: %s\n\n"
       .. "=== /var/log/sudhanix-pam-cache.log (tail 20) ===\n%s\n\n"
       .. "=== /run/sudhanix-tokens/ ===\n%s",
          r.returncode,
          r.stdout, r.stderr,
          (log_tail.ok and log_tail.stdout) or log_tail.stderr,
          (token_ls.ok and token_ls.stdout) or token_ls.stderr
        )

        return {
          ok = r.ok,
          title = r.ok and ("Auth succeeded for " .. user) or ("Auth failed for " .. user),
          body = table.concat(body_lines, "\n"),
          details = details,
        }
      end,
    },
  },
}
