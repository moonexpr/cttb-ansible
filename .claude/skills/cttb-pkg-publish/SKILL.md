---
name: cttb-pkg-publish
user-invocable: false
description: >
  Build a cargo-deb package on the buildworker LXC and publish it to
  the apt.cttb extras pool via reprepro. Agent-only generalization of
  `/vajra-build` for any cargo workspace that produces a single .deb.
  Triggers when an agent has a vajra-shaped publish need for a
  package that is not vajra. Today, the implementation is a stub —
  /vajra-build is the only active consumer; this skill captures the
  generic shape for the next package.
---

# cttb-pkg-publish

Generic version of `/vajra-build`. Same nine-step pipeline (stage → start buildworker → push → cargo build → cargo deb → pull → ship via mac bridge → reprepro include → stop container) parameterized over package identity rather than hardcoded for vajra.

## Status: design captured, implementation deferred

The script for this skill is **not yet written**. `/vajra-build/scripts/publish.sh` is the working reference implementation, with vajra-specific paths inlined. Factoring it into a generic skeleton has real cost (parameterize source path, workspace member, .deb naming, post-install verification target) and the payoff only arrives with a second package. Until then:

- For vajra: use `/vajra-build` directly.
- For a hypothetical second cargo workspace package: factor `/vajra-build/scripts/publish.sh` into this skill's `scripts/publish.sh` as the first task of that effort. The 9-step structure is reusable as-is; only the parameters change.

## Procedure (planned)

When implemented, the resource script will accept:

```
bash .claude/skills/cttb-pkg-publish/scripts/publish.sh \
    --pkg <name> \
    --src <path> \
    --workspace-member <crate>
```

And read the package version + revision from `<src>/<workspace-member>/Cargo.toml`'s `[package]` and `[package.metadata.deb]` blocks, the same way `/vajra-build` does today.

Pipeline identical to `/vajra-build` except parameterized:

1. Stage source from `<src>` to `/tmp/<pkg>-stage` via rsync with anchored excludes (`/target/`, `/.git/`, `/legacy/`, `.DS_Store`, `._*`).
2. `lxc start buildworker` (idempotent).
3. Tar-pipe staged tree into `buildworker:/root/<pkg>-build`.
4. `cargo build --release --workspace && cargo deb --no-build -p <workspace-member>` on buildworker.
5. Pull `<pkg>_<version>-<revision>_amd64.deb` to srv-vm:/tmp/.
6. Bridge via mac to srv-nas (srv-vm → mac → srv-nas; the direct route is flaky).
7. `lxc file push` into debmirror; `reprepro remove + includedeb noble + export + list noble <pkg>`.
8. Cleanup on success; leave work dir on failure for debugging; always `lxc stop buildworker` via EXIT trap.
9. Surface `noble|main|amd64: <pkg> <version>` as the success signal.

## Migration plan

When this skill's `scripts/publish.sh` lands:

1. Author the parameterized script as described above; verify by invoking it for vajra with `--pkg vajra --src "$VAJRA_SRC" --workspace-member vajra-gtk`.
2. Confirm the recap matches what `/vajra-build` produces today.
3. Refactor `/vajra-build/scripts/publish.sh` into a one-line wrapper that invokes `/cttb-pkg-publish` with vajra's parameters. `/vajra-build`'s SKILL.md stays as the project-specific trigger; the pipeline source-of-truth moves here.

This skill exists as a placeholder so that when the second package arrives, the design conversation does not have to be rerun — the shape is captured.

## Resources

| File | Loaded / run when |
|---|---|
| `scripts/publish.sh` | **Not yet written.** Author when a second cargo workspace package needs publishing; refactor /vajra-build to call it. |
