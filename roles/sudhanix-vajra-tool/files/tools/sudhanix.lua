-- sudhanix — campus desktop diagnostics, launchers, and identity tools.
--
-- Status rows: hostname, sudhanix release, kernel, display server, uptime.
-- Actions: open welcome panel, plymouth boot test, system info, font explorer,
-- wallpaper folder, keyboard shortcut editor, sound mixer/test, CUPS debug,
-- NFS mount debug, set hostname (with auto-emailed DNS change request).

local function trim(s)
  return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function or_else(s, fallback)
  if s and s ~= "" then return s end
  return fallback
end

local function exists(ctx, path)
  return ctx:run({ "test", "-e", path }, { timeout = 3 }).returncode == 0
end

local function is_file(ctx, path)
  return ctx:run({ "test", "-f", path }, { timeout = 3 }).returncode == 0
end

local function is_dir(ctx, path)
  return ctx:run({ "test", "-d", path }, { timeout = 3 }).returncode == 0
end

local function read_file(ctx, path)
  if not is_file(ctx, path) then
    return string.format("(missing: %s)", path)
  end
  local r = ctx:run({ "cat", "--", path }, { timeout = 5 })
  if r.returncode ~= 0 then
    return string.format("(unreadable: %s)", trim(r.stderr))
  end
  return r.stdout
end

local function looks_like_hostname(name)
  if not name or name == "" or #name > 63 then return false end
  if name:sub(1, 1) == "-" or name:sub(-1) == "-" then return false end
  for c in name:gmatch(".") do
    if not c:match("[%w%-]") then return false end
  end
  return true
end

local function primary_mac(ctx)
  local out = ctx:run({ "ip", "-o", "link" }, { timeout = 5 }).stdout
  for line in out:gmatch("[^\n]+") do
    if line:find("link/ether", 1, true) then
      local iface = line:match("^%d+:%s+(%S+):") or ""
      if iface ~= "lo" then
        local mac = line:match("link/ether%s+([0-9a-fA-F:]+)")
        if mac then return mac end
      end
    end
  end
  return "(unknown)"
end

-- Map env vars surfaced via /usr/bin/env so we don't need a Lua os.getenv.
local function getenv_via_run(ctx, name)
  local r = ctx:run({ "sh", "-c", string.format('printf "%%s" "${%s-}"', name) }, { timeout = 3 })
  return r.stdout or ""
end

local function read_release(ctx)
  for _, p in ipairs({ "/etc/sudhanix-release", "/etc/sudhanix_version" }) do
    if is_file(ctx, p) then
      local r = ctx:run({ "cat", "--", p }, { timeout = 3 })
      local s = trim(r.stdout)
      if s ~= "" then return s end
    end
  end
  local s = trim(ctx:run({ "lsb_release", "-ds" }, { timeout = 5 }).stdout)
  if s ~= "" then return s end
  return "unknown"
end

local function find_and_spawn(ctx, candidates, label_fmt)
  for _, argv in ipairs(candidates) do
    if ctx:has(argv[1]) then
      ctx:spawn(argv)
      return { ok = true, title = string.format(label_fmt, argv[1]) }
    end
  end
  return nil
end

return {
  id = "sudhanix",
  label = "Sudhanix",
  category = "Sudhanix",
  icon = "start-here",
  description = "Campus desktop status, launchers, and diagnostics.",
  required_groups = { "it", "sudo", "wheel", "admin" },
  order = 5,

  statuses = {
    {
      name = "hostname",
      label = "Hostname",
      order = 10,
      runner = function(ctx)
        local s = trim(ctx:run({ "hostnamectl", "--static" }, { timeout = 5 }).stdout)
        if s ~= "" then return s end
        return trim(ctx:run({ "hostname" }, { timeout = 5 }).stdout)
      end,
    },
    {
      name = "sudhanix_release",
      label = "Sudhanix release",
      order = 20,
      runner = function(ctx) return read_release(ctx) end,
    },
    {
      name = "kernel",
      label = "Kernel",
      order = 30,
      runner = function(ctx)
        return trim(ctx:run({ "uname", "-r" }, { timeout = 5 }).stdout)
      end,
    },
    {
      name = "display",
      label = "Display server",
      order = 40,
      runner = function(ctx)
        local wayland = getenv_via_run(ctx, "WAYLAND_DISPLAY")
        if wayland ~= "" then return string.format("Wayland (%s)", wayland) end
        local display = getenv_via_run(ctx, "DISPLAY")
        if display ~= "" then
          local session = or_else(getenv_via_run(ctx, "XDG_SESSION_TYPE"), "x11")
          return string.format("%s (%s)", session, display)
        end
        return "(none)"
      end,
    },
    {
      name = "uptime",
      label = "Uptime",
      order = 50,
      runner = function(ctx)
        return or_else(trim(ctx:run({ "uptime", "-p" }, { timeout = 5 }).stdout), "?")
      end,
    },
  },

  actions = {
    {
      name = "open_welcome",
      label = "Open welcome panel",
      description = "Re-open the first-login welcome window.",
      button_label = "Open",
      runner = function(ctx)
        local welcome = "/usr/local/bin/sudhanix-welcome"
        if not is_file(ctx, welcome) then
          return {
            ok = false,
            title = "Welcome panel not installed",
            body = string.format("%s is missing on this host.", welcome),
            details = "Install or restore the sudhanix-welcome package, or run the desktop role.",
          }
        end
        local ok, err = pcall(function() ctx:spawn({ welcome }) end)
        if not ok then
          return {
            ok = false,
            title = "Failed to launch welcome panel",
            details = tostring(err),
          }
        end
        return { ok = true, title = "Welcome panel launched", body = "Window may take a few seconds to render." }
      end,
    },

    {
      name = "show_sysinfo",
      label = "System information",
      description = "CPU, memory, storage, and OS overview for this host.",
      button_label = "Show",
      runner = function(ctx)
        local cpu_model = trim(ctx:run(
          { "sh", "-c", "grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2-" },
          { timeout = 3 }
        ).stdout)
        if cpu_model == "" then cpu_model = "?" end
        local cpu_logical = trim(ctx:run(
          { "sh", "-c", "grep -c '^processor' /proc/cpuinfo" },
          { timeout = 3 }
        ).stdout)
        local cpu_phys = trim(ctx:run(
          { "sh", "-c", "lscpu | awk -F: '/^Socket/ {s=$2} /^Core/ {c=$2} END {gsub(/^ +/, \"\", s); gsub(/^ +/, \"\", c); if (s && c) printf \"%d\", s*c; else printf \"?\"}'" },
          { timeout = 3 }
        ).stdout)
        if cpu_phys == "" then cpu_phys = "?" end

        local mem_total = trim(ctx:run(
          { "sh", "-c", "free -h | awk '/^Mem:/ {print $2}'" },
          { timeout = 3 }
        ).stdout)
        if mem_total == "" then mem_total = "?" end

        local hostname = trim(ctx:run({ "hostname", "-f" }, { timeout = 3 }).stdout)
        if hostname == "" then hostname = trim(ctx:run({ "hostname" }, { timeout = 3 }).stdout) end
        local kernel = trim(ctx:run({ "uname", "-r" }, { timeout = 3 }).stdout)
        local uptime = or_else(trim(ctx:run({ "uptime", "-p" }, { timeout = 3 }).stdout), "?")
        local arch = trim(ctx:run({ "uname", "-m" }, { timeout = 3 }).stdout)
        local osrel = read_release(ctx)

        local body = string.format(
          "Host:      %s\nOS:        %s\nKernel:    %s (%s)\nCPU:       %s\n           %s physical / %s logical cores\nRAM:       %s total\nUptime:    %s",
          hostname, osrel, kernel, arch, cpu_model, cpu_phys, cpu_logical, mem_total, uptime
        )

        local lscpu  = ctx:run({ "lscpu" }, { timeout = 5 }).stdout
        local memout = ctx:run({ "free", "-h" }, { timeout = 3 }).stdout
        local diskout = ctx:run(
          { "df", "-h", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs", "-x", "overlay" },
          { timeout = 5 }
        ).stdout
        local lsblk = ctx:run(
          { "lsblk", "-o", "NAME,SIZE,TYPE,MOUNTPOINTS", "-e", "7" },
          { timeout = 5 }
        ).stdout
        local primary_iface = ""
        for line in (ctx:run({ "ip", "route", "show", "default" }, { timeout = 3 }).stdout):gmatch("[^\n]+") do
          local dev = line:match("dev%s+(%S+)")
          if dev then primary_iface = dev; break end
        end
        local ip_block = ctx:run({ "ip", "-br", "addr" }, { timeout = 3 }).stdout

        local function section(title, content)
          return string.format("=== %s ===\n%s", title, (content or ""):gsub("%s+$", ""))
        end

        local details = table.concat({
          section("CPU (lscpu)", lscpu),
          section("Memory (free -h)", memout),
          section("Filesystems (df -h)", diskout),
          section("Block devices (lsblk)", lsblk),
          section(string.format("Network (primary iface: %s)", primary_iface ~= "" and primary_iface or "?"),
            ip_block),
        }, "\n\n")

        return {
          ok = true,
          title = "System information",
          body = body,
          details = details,
        }
      end,
    },

    {
      name = "open_fonts",
      label = "Font explorer",
      description = "Browse installed fonts.",
      button_label = "Open",
      runner = function(ctx)
        local launched = find_and_spawn(ctx,
          { { "font-manager" }, { "gnome-font-viewer" } },
          "Launched %s")
        if launched then return launched end
        ctx:open_path("/usr/share/fonts")
        return { ok = true, title = "Opened /usr/share/fonts in file manager" }
      end,
    },

    {
      name = "open_wallpapers",
      label = "Wallpapers folder",
      description = "Open the campus wallpaper directory in the file manager.",
      button_label = "Open",
      runner = function(ctx)
        for _, path in ipairs({
          "/usr/share/backgrounds/sudhanix",
          "/usr/share/backgrounds/cttb",
          "/usr/share/backgrounds",
        }) do
          if is_dir(ctx, path) then
            ctx:open_path(path)
            return { ok = true, title = string.format("Opened %s", path) }
          end
        end
        return { ok = false, title = "No wallpaper folder found" }
      end,
    },

    {
      name = "open_keyboard",
      label = "Keyboard shortcut editor",
      description = "Open xfce4-keyboard-settings to inspect or rebind shortcuts.",
      button_label = "Open",
      runner = function(ctx)
        ctx:spawn({ "xfce4-keyboard-settings" })
        return { ok = true, title = "Launched xfce4-keyboard-settings" }
      end,
    },

    {
      name = "open_mixer",
      label = "Sound mixer",
      description = "Open the volume / device mixer.",
      button_label = "Open",
      runner = function(ctx)
        local launched = find_and_spawn(ctx,
          { { "pavucontrol" }, { "pwvucontrol" }, { "xfce4-pulseaudio-plugin-settings" } },
          "Launched %s")
        if launched then return launched end
        return { ok = false, title = "No sound mixer installed" }
      end,
    },

    {
      name = "play_test_sound",
      label = "Play test sound",
      description = "Play a built-in event sound to verify audio output.",
      button_label = "Play",
      fields = {
        {
          name = "event",
          label = "Event sound",
          kind = "choice",
          choices = { "bell", "complete", "message", "device-added", "alarm-clock-elapsed" },
          default = "bell",
        },
      },
      runner = function(ctx, fields)
        if not ctx:has("canberra-gtk-play") then
          return {
            ok = false,
            title = "canberra-gtk-play not installed",
            body = "Install libcanberra-gtk3-module to enable test sounds.",
          }
        end
        local event = fields.event ~= "" and fields.event or "bell"
        local r = ctx:run({ "canberra-gtk-play", "-i", event }, { timeout = 10 })
        if r.returncode ~= 0 then
          return { ok = false, title = "Failed to play", details = r.stderr ~= "" and r.stderr or r.stdout }
        end
        return { ok = true, title = string.format("Played: %s", event) }
      end,
    },

    {
      name = "plymouth_status",
      label = "Plymouth boot screen status",
      description = "Show the active boot splash theme, available themes, and unit status. Does not run the splash — that has to happen at real boot, since starting plymouthd on top of a running X session leaves the framebuffer in a stuck state.",
      button_label = "Show",
      runner = function(ctx)
        if not ctx:has("plymouth-set-default-theme") then
          return {
            ok = false,
            title = "plymouth not installed",
            body = "Install the plymouth + plymouth-themes packages to use the campus boot splash.",
          }
        end
        local current = trim(ctx:run({ "plymouth-set-default-theme" }, { timeout = 5 }).stdout)
        local available = ctx:run({ "plymouth-set-default-theme", "-l" }, { timeout = 5 }).stdout
        local units = ctx:run(
          { "systemctl", "status", "--no-pager", "-n", "0",
            "plymouth-start.service",
            "plymouth-quit.service",
            "plymouth-quit-wait.service",
            "plymouth-read-write.service" },
          { timeout = 5 }
        ).stdout
        local enabled = trim(ctx:run({ "systemctl", "is-enabled", "plymouth-start.service" },
          { timeout = 5 }).stdout)

        local body = string.format(
          "Active theme:    %s\nplymouth-start:  %s\nNote:            run a real reboot to verify the splash visually — vajra cannot exercise it on a live desktop without locking the framebuffer.",
          current ~= "" and current or "?",
          enabled ~= "" and enabled or "?"
        )
        local details = string.format(
          "=== plymouth-set-default-theme -l ===\n%s\n=== unit status ===\n%s",
          (available or ""):gsub("%s+$", ""),
          (units or ""):gsub("%s+$", "")
        )
        return { ok = true, title = "Plymouth status", body = body, details = details }
      end,
    },

    {
      name = "debug_cups",
      label = "Debug CUPS",
      description = "Show printer status, daemon health, and client config.",
      button_label = "Run",
      runner = function(ctx)
        local sections = {
          { "lpstat -t", ctx:run({ "lpstat", "-t" }, { timeout = 10 }).stdout },
          { "systemctl status cups",
            ctx:run({ "systemctl", "status", "cups", "--no-pager", "-n", "20" }, { timeout = 10 }).stdout },
          { "client.conf", read_file(ctx, "/etc/cups/client.conf") },
          { "default printer", ctx:run({ "lpstat", "-d" }, { timeout = 5 }).stdout },
        }
        local out = {}
        for _, s in ipairs(sections) do
          out[#out + 1] = string.format("=== %s ===\n%s", s[1], (s[2] or ""):gsub("%s+$", ""))
        end
        local first = sections[1][2] or ""
        local body = "(no printers)"
        for line in first:gmatch("[^\n]+") do
          if trim(line) ~= "" then body = line; break end
        end
        return { ok = true, title = "CUPS diagnostics", body = body, details = table.concat(out, "\n\n") }
      end,
    },

    {
      name = "debug_nfs",
      label = "Debug NFS mounts",
      description = "Show NFS mount table, free space, and autofs config.",
      button_label = "Run",
      runner = function(ctx)
        local mount_text = ctx:run({ "mount" }, { timeout = 10 }).stdout
        local nfs_lines = {}
        for line in mount_text:gmatch("[^\n]+") do
          if line:find("nfs", 1, true) then nfs_lines[#nfs_lines + 1] = line end
        end
        local nfs_block = #nfs_lines > 0 and table.concat(nfs_lines, "\n") or "(no NFS mounts)"
        local fstab_lines = {}
        for line in (read_file(ctx, "/etc/fstab")):gmatch("[^\n]+") do
          if line:find("nfs", 1, true) then fstab_lines[#fstab_lines + 1] = line end
        end
        local fstab_block = #fstab_lines > 0 and table.concat(fstab_lines, "\n") or "(none)"
        local sections = {
          { "mount (NFS)", nfs_block },
          { "df -h (NFS)", ctx:run({ "df", "-h", "-t", "nfs", "-t", "nfs4" }, { timeout = 10 }).stdout },
          { "/etc/auto.master", read_file(ctx, "/etc/auto.master") },
          { "/etc/fstab (NFS lines)", fstab_block },
          { "rpcinfo -p", ctx:run({ "rpcinfo", "-p" }, { timeout = 10 }).stdout },
        }
        local out = {}
        for _, s in ipairs(sections) do
          out[#out + 1] = string.format("=== %s ===\n%s", s[1], (s[2] or ""):gsub("%s+$", ""))
        end
        local body = #nfs_lines > 0 and nfs_lines[1] or "No NFS mounts active"
        return { ok = true, title = "NFS diagnostics", body = body, details = table.concat(out, "\n\n") }
      end,
    },

    {
      name = "set_hostname",
      label = "Set hostname",
      description = "Change this machine's hostname locally and email IT to update DNS/DHCP.",
      confirm = "Set the hostname locally and open an email to IT?",
      privileged = true,
      button_label = "Set + email IT",
      fields = {
        { name = "new_hostname", label = "New hostname", placeholder = "e.g. dvgs-lab1" },
        {
          name = "reason",
          label = "Reason / notes",
          kind = "multiline",
          required = false,
          placeholder = "(Optional) Why this change?",
        },
      },
      runner = function(ctx, fields)
        local new_name = trim(fields.new_hostname or "")
        if not looks_like_hostname(new_name) then
          return {
            ok = false,
            title = "Invalid hostname",
            body = "Hostnames are 1-63 chars: letters, digits, hyphens. No leading/trailing hyphen.",
          }
        end
        local old_name = trim(ctx:run({ "hostname" }, { timeout = 5 }).stdout)
        if new_name == old_name then
          return {
            ok = false,
            title = "Hostname unchanged",
            body = string.format("Already %s.", old_name),
          }
        end
        local r = ctx:run_privileged({ "hostnamectl", "set-hostname", new_name }, { timeout = 10 })
        if r.returncode ~= 0 then
          return { ok = false, title = "hostnamectl failed", details = r.stderr ~= "" and r.stderr or r.stdout }
        end

        local cfg = ctx:config("sudhanix")
        local it_email = "it@cttb.org"
        if type(cfg) == "table" and cfg.it_email and cfg.it_email ~= "" then
          it_email = cfg.it_email
        end

        local mac = primary_mac(ctx)
        local ip = or_else(trim(ctx:run({ "hostname", "-I" }, { timeout = 5 }).stdout), "(unknown)")

        local lines = {
          "Hi IT,",
          "",
          "Please update the DNS / DHCP records for this workstation:",
          "",
          string.format("  Old hostname:  %s", old_name),
          string.format("  New hostname:  %s", new_name),
          string.format("  MAC:           %s", mac),
          string.format("  IP:            %s", ip),
          string.format("  Changed by:    %s", ctx.user),
        }
        local reason = trim(fields.reason or "")
        if reason ~= "" then
          lines[#lines + 1] = ""
          lines[#lines + 1] = "Reason:"
          lines[#lines + 1] = reason
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Thanks!"

        local subject = string.format("DNS change: %s -> %s", old_name, new_name)
        ctx:compose_email(it_email, subject, table.concat(lines, "\n"))

        return {
          ok = true,
          title = string.format("Hostname set to %s", new_name),
          body = string.format("Email opened to %s. Reboot recommended.", it_email),
          details = table.concat(lines, "\n"),
        }
      end,
    },
  },
}
