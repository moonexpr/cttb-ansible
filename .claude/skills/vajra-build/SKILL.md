---
name: vajra-build
description: Build the vajra Debian package on the buildworker LXC and publish it to the apt.cttb extras pool via reprepro. One closed pipeline — stage source, start container, push, cargo build + cargo deb, pull artifact, ship via mac bridge, reprepro includedeb noble, verify, cleanup, stop container. TRIGGER on `/vajra-build`, "build and publish the vajra .deb", "ship a new vajra release", "publish vajra to apt.cttb", or a vajra commit ready to ship.
---

# /vajra-build

End-to-end vajra .deb publish. One job: take whatever is currently committed at your local vajra checkout (`${VAJRA_SRC}` — set in `.env`, see `.claude/.env.example`) and ship it to apt.cttb's `noble/main/amd64` pool.

The pipeline runs unattended through nine steps and stops itself on completion. The buildworker LXC starts when the script needs it and stops when the script is done — it does not sit warm between builds.

## Procedure

Run the resource script:

```
bash .claude/skills/vajra-build/scripts/publish.sh
```

The script executes, in order:

1. **Stage source** to `/tmp/vajra-stage` via `rsync` with anchored excludes. The leading slash on `/target/`, `/.git/`, `/legacy/` is load-bearing — the source tree's `vendor/` directory contains real crate code in directories named `target` (e.g. `vendor/cc/src/target/`) and `legacy` (e.g. `vendor/hyper-util/src/client/legacy/`) that must NOT be excluded.
2. **Start buildworker** via `ssh srv-vm "lxc start buildworker"`. Idempotent — already-running is not a failure.
3. **Push source** by tar-piping the staged tree into `buildworker:/root/vajra-build`.
4. **Build**: `cargo build --release --workspace` + `cargo deb --no-build -p vajra-gtk` on buildworker.
5. **Pull the .deb** to `srv-vm:/tmp/` via `lxc file pull`.
6. **Bridge via mac** to `srv-nas` — the direct `srv-vm → srv-nas` SCP route has been flaky, so the script goes `srv-vm → mac → srv-nas`.
7. **Reprepro publish**: `lxc file push` into the debmirror container, then `reprepro remove + includedeb noble + export noble + list noble vajra`. The `list` output is the verification.
8. **Cleanup**: on success, delete the work dir on buildworker, the `.deb` at every hop, and the local stage dir. On failure, leave the work dir on buildworker for debugging.
9. **Stop buildworker** (always — registered as an `EXIT` trap so it stops even when the script fails mid-pipeline).

Success prints one line to stderr:

```
[vajra-build] published: noble|main|amd64: vajra <version>
```

Exit codes: `0` on success, `1` on the first failed step. Each step logs its label to stderr before running, so the failure point is visible from the log.

## Prerequisites

The operator must have working SSH to `srv-vm` and `srv-nas` (configured in `~/.ssh/config`; CTTB sudo available on `srv-nas`). Buildworker must already be provisioned with rustup at `/root/.cargo`, `cargo-deb` on PATH, the Ubuntu noble apt sources, and `libgtk-3-dev` + `build-essential`. This is one-time setup; the container state persists between runs.

The published version is read from `vajra-gtk/Cargo.toml`'s `[package].version` and `[package.metadata.deb].revision`. Bump `revision` in Cargo.toml before re-publishing a packaging-only change so apt sees the new package as newer.

## Resources

| File | Loaded / run when |
|---|---|
| `scripts/publish.sh` | Run on every `/vajra-build` invocation. The actual pipeline. |
