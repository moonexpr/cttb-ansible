May 4th, 2026 - Remaining Items

Must Fix:
* LDAP auth — TLS/STARTTLS handshake failing (nscd logs: `do_start_tls failed`). LDAP server at ldap.cttb (10.11.1.25) reachable on port 389, but port 636 refused. PAM/NSS config is correct. Fix requires LDAP server-side TLS config or disabling TLS in ldap.conf.
* Upload fresh Zoom .deb to storehouse — current file is corrupted (4.3KB HTML error page). Fresh 281MB .deb downloaded to `/tmp/zoom_new.deb` on testmachine from zoom.us.
* New greeter avatars for the three schools
* Full clean playbook run with --skip-tags zoom
* devilspie2 not starting on login — XFCE session and Plank run but devilspie2 absent from process list. Desktop renders black. Check autostart config and Lua script syntax.

Should Fix:
* Verify greeter CSS on physical monitor
* Fix SSH ProxyJump via Tailscale (intermittent)
