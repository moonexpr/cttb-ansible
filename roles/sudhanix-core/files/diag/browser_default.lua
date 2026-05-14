-- browser_default.lua — standalone diagnostic for default-browser
-- dispatch failures (gh-62: "Failed to execute default Web Browser.
-- Input/output error.")
--
-- Run as the logged-in user, in a desktop session:
--
--   vajra lua /usr/local/share/sudhanix/diag/browser_default.lua
--
-- Or over SSH from the operator's laptop:
--
--   ssh administrator@<host> 'bash -lc "vajra lua /usr/local/share/sudhanix/diag/browser_default.lua"'
--
-- The `bash -lc` form is load-bearing: a non-login SSH shell has
-- XDG_DATA_DIRS="" and Flatpak .desktop files (Zen) are invisible to
-- xdg-mime. /etc/profile.d/flatpak.sh populates the env in a real
-- login shell. The welcome panel and the XFCE app launcher both run
-- in a login env, so the operator should match that.
--
-- Walks the full chain:
--   1. user / system mimeapps.list precedence stack
--   2. what xdg-mime / xdg-settings actually resolve right now
--   3. for each candidate browser .desktop:
--        - is the .desktop file findable on XDG_DATA_DIRS?
--        - what's its Exec= line?
--        - does the named binary actually exist on PATH?
-- The last step is what catches the gh-86 firefox-snap-stub case:
-- xdg-settings happily writes "firefox.desktop" into mimeapps.list,
-- but the Exec target is missing → runtime error.

local function trim(s) return (s or ""):gsub("%s+$", "") end

local function exists(path)
  return ctx:run({"test", "-e", path}).ok
end

local function head(path, n)
  if not exists(path) then return nil end
  local r = ctx:run({"head", "-n", tostring(n or 30), path})
  return r.stdout
end

local CANDIDATES = {
  "google-chrome.desktop",
  "com.google.Chrome.desktop",     -- portal-aware duplicate (NoDisplay=true)
  "firefox.desktop",
  "firefox-esr.desktop",
  "app.zen_browser.zen.desktop",   -- Flatpak (under /var/lib/flatpak/exports/share/applications/)
}

local MIMES = {
  "text/html",
  "application/xhtml+xml",
  "application/xml",
  "x-scheme-handler/http",
  "x-scheme-handler/https",
  "x-scheme-handler/about",
  "x-scheme-handler/unknown",
  "x-scheme-handler/ftp",
  "application/x-extension-htm",
  "application/x-extension-html",
  "application/x-extension-shtml",
  "application/x-extension-xhtml",
  "application/x-extension-xht",
}

print("=== environment ===")
print(string.format("  user            : %s", ctx.user))
print(string.format("  HOME            : %s", ctx.home))
print(string.format("  XDG_DATA_DIRS   : %s", (os.getenv("XDG_DATA_DIRS") or "<unset>")))
print(string.format("  DISPLAY         : %s", os.getenv("DISPLAY") or "<unset>"))
if not os.getenv("XDG_DATA_DIRS") or os.getenv("XDG_DATA_DIRS") == "" then
  print("  [!] XDG_DATA_DIRS empty — Flatpak .desktop files will not be found.")
  print("      Re-invoke via `bash -lc` to source /etc/profile.d/*.sh.")
end

print()
print("=== mimeapps.list layers (highest precedence first) ===")
local layers = {
  ctx.home .. "/.config/mimeapps.list",
  ctx.home .. "/.local/share/applications/mimeapps.list",
  "/etc/xdg/mimeapps.list",
  "/usr/share/applications/mimeapps.list",
  "/usr/local/share/applications/mimeapps.list",
}
for _, p in ipairs(layers) do
  print(string.format("  %-60s : %s", p, exists(p) and "present" or "absent"))
end

print()
print("=== xdg-settings get default-web-browser ===")
local r = ctx:run({"xdg-settings", "get", "default-web-browser"})
print("  " .. trim(r.stdout))

print()
print("=== xdg-mime query default — resolved chain ===")
for _, mime in ipairs(MIMES) do
  local rr = ctx:run({"xdg-mime", "query", "default", mime})
  print(string.format("  %-35s -> %s", mime,
    (rr.ok and #rr.stdout > 0) and trim(rr.stdout) or "<none>"))
end

print()
print("=== candidate browser .desktop files — does each actually work? ===")
for _, desktop in ipairs(CANDIDATES) do
  print(string.format("  --- %s ---", desktop))

  local found = ctx:run({"sh", "-c", string.format([[
    for d in $(echo "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' '\n') /usr/local/share /usr/share; do
      if [ -f "$d/applications/%s" ]; then
        echo "$d/applications/%s"
        break
      fi
    done
  ]], desktop, desktop)})

  local path = trim(found.stdout)
  if path == "" then
    print("    NOT FOUND on XDG_DATA_DIRS")
  else
    print(string.format("    found at      : %s", path))
    local exec = ctx:run({"grep", "-m1", "^Exec=", path})
    local exec_line = trim(exec.stdout)
    print(string.format("    Exec=         : %s", exec_line))
    local bin = exec_line:match("Exec=([^ ]+)")
    if bin then
      local w = ctx:run({"which", bin})
      if w.ok then
        print(string.format("    binary on PATH: %s (OK)", trim(w.stdout)))
      else
        -- Could be an absolute path inside the .desktop.
        local abs_check = ctx:run({"test", "-x", bin})
        if abs_check.ok then
          print(string.format("    binary on PATH: %s (absolute, OK)", bin))
        else
          print(string.format("    binary on PATH: MISSING — Exec=%s not found", bin))
          print(string.format("                    this is the gh-62 \"Input/output error\" path"))
        end
      end
    end
  end
end

print()
print("=== summary ===")
local html_handler = ""
do
  local rr = ctx:run({"xdg-mime", "query", "default", "text/html"})
  html_handler = (rr.ok) and trim(rr.stdout) or "<none>"
end
print(string.format("  Default web browser (text/html): %s", html_handler))

-- Check whether the resolved handler actually has a working Exec target.
if html_handler ~= "" and html_handler ~= "<none>" then
  local found = ctx:run({"sh", "-c", string.format([[
    for d in $(echo "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' '\n') /usr/local/share /usr/share; do
      [ -f "$d/applications/%s" ] && { echo "$d/applications/%s"; break; }
    done
  ]], html_handler, html_handler)})
  local path = trim(found.stdout)
  if path == "" then
    print("  [✗] Resolved .desktop file does not exist — dispatch will fail.")
  else
    local exec = ctx:run({"grep", "-m1", "^Exec=", path})
    local bin = trim(exec.stdout):match("Exec=([^ ]+)")
    local ok = false
    if bin then
      ok = (ctx:run({"which", bin}).ok) or (ctx:run({"test", "-x", bin}).ok)
    end
    if ok then
      print("  [✓] Resolved handler's Exec target exists — should dispatch cleanly.")
    else
      print("  [✗] Resolved handler's Exec target is MISSING — dispatch will I/O-error.")
      print("      Fix: install the missing binary, or pick a different browser in")
      print("      welcome (or via `xdg-settings set default-web-browser ...`).")
    end
  end
end
