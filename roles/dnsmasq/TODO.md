# roles/dnsmasq — TODO

Tracked centrally in **cttb-ansible#89**. This file is the working list.

- [ ] **git ⇄ deployed drift (decide source of truth).** Deployed
      `/etc/dnsmasq.conf` is 351 lines; git
      (`~/Garden/external/dnsmasq`) HEAD is 344 and last touched the
      conf in 2017. Deployed `/etc/dnsmasq-hosts` has 6 files; git
      tracks 15 (`restricted/servers/switches/visitors/voip/waps`/…).
      The role template was lifted from the **deployed** file (the
      running truth). Decide whether the repo or the box is canonical,
      converge them, then consider flipping
      `dnsmasq_manage_hosts_content` to `true`.
- [ ] **hosts-content ownership.** Until the drift above is resolved
      the role only manages the directory. Folding `register.py` /
      `next-ip.py` and the per-population files into Ansible (or into a
      committed repo the role checks out) removes the last
      out-of-band, un-backed-up surface.
- [ ] **dead backup box.** `lxc-bk-dnsmasq` (`10.11.1.86`) is
      unreachable; Vincent's 2023 `*/10 * * * *` rsync of
      `/etc/dnsmasq-hosts` has been failing silently. The backup story
      must move into git / the role, not a dead peer.
- [ ] **`log-queries`.** Historical config logs every query — heavy on
      ~1,100 clients. `dnsmasq_log_queries` preserves it for now;
      choose a sampled / rate-limited alternative and default it off.
- [ ] **`--local-service` review.** The unit launches with
      `--local-service` (DNS answered only to local-subnet sources).
      Confirm every segment that queries `.19` directly is on-subnet;
      if the Earth Store Hall AP is routed from elsewhere, the upstream
      snippet alone will not be enough.
- [ ] **24.04 rebuild.** This role is ready for it; execution is
      `docs/dnsmasq-24.04-migration.md`. Cutover gated, not automated.
- [ ] **Monitoring (SP Monitoring).** Alert on (a) `:53` on `.19`
      failing an external name, (b) lease-file mtime not advancing
      (DHCP-down detector — the signature of this incident).
