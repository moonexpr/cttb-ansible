# Status and remaining work

As of 2026-05-15, Sudhanix 26 core development is complete. The configuration
is frozen at the `sudhanix26.0.0` tag, and the project is in its documentation
and optimization phase until demo and release. Every release blocker is closed,
the final clean run is gold-standard verified on a pristine PXE image, and the
work that remains needs an operator or a deliberate optimization pass rather
than new core code.

This file is a signpost, not the work list. The canonical tracker is GitHub
issues on `moonexpr/cttb-ansible`, grouped by milestone. Filing and triage
happen there so a single stale snapshot cannot drift out from under the work,
which is the reason the old `BACKLOG.md` was retired.

What remains falls into four groups.

**Operator-gated rollout.** Issue 16 tasks 2 through 4: reimage and configure
the DVGS, DVBS, and DRBU labs with `sudhanix26-rollout`, one host at a time or
the staged batch pattern for a full lab. Task 1, the clean fresh-image run, is
already verified. `DEPLOYMENT.md` carries the procedure.

**Optimization candidates.** The squashfs PXE fetch, a VM test pipeline, and
the autostrap-versus-metapackage decision are the highest-leverage items for
making the rollout faster and the fresh-image test cheap. These are scoped on
the issue tracker, not here.

**At-seat verification.** The visual cluster, orange text, dock strut, plymouth
polish, and greeter CSS on a physical monitor, cannot be confirmed over SSH and
waits on an operator at the seat.

**Known niggles.** The Zoom `.deb` ships an invalid archive signature, so every
rollout run carries `--skip-tags zoom`, and the upstream `.deb` still needs a
clean restage on storehouse. SSH ProxyJump over Tailscale is intermittent. Both
are tracked on GitHub.
