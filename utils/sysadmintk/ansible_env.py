"""
Ansible environment resolution for this repository — stdlib only.

  AnsibleContext   the repo's resolved paths and ANSIBLE_* variables

One place decides which inventory a command talks to. Previously `utils/setup-env`
hardcoded it and every wrapper passed it as an explicit `-i`, which silently
overrode `ansible.cfg` — so the config file naming a different inventory was dead
and nobody could tell which fleet a play would reach.

Precedence, highest first:

  1. `-i` on the ansible command line   (ansible's own handling)
  2. $ANSIBLE_INVENTORY                 (honoured here)
  3. <repo>/inventory/hosts             (this repo's default)
"""
from __future__ import annotations

import os
import shlex
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from cttb_api import CttbContext


def repo_root() -> Path:
    """Repository root via git, falling back to the working directory when git
    is unavailable or this is a plain deployment (tarball, rsync)."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return Path.cwd()
    return Path(out) if out else Path.cwd()


@dataclass(frozen=True)
class AnsibleContext(CttbContext):
    """Resolved Ansible environment. Build with `.default()`; everything other
    than `base` and `inventory` is derived, so the parts cannot disagree.

    `inventory` is a string rather than a Path because ANSIBLE_INVENTORY is a
    pathlist — a caller may legitimately pass a comma-separated set of sources.
    """

    base: Path
    inventory: str

    @classmethod
    def default(cls) -> "AnsibleContext":
        base = repo_root()
        override = os.environ.get("ANSIBLE_INVENTORY")
        inventory = override or str(base / "inventory" / "hosts")
        return cls(base=base, inventory=inventory)

    # ── derived paths ─────────────────────────────────────────────────────────

    @property
    def playbooks(self) -> Path:
        return self.base / "plays"

    @property
    def roles(self) -> Path:
        return self.base / "roles"

    @property
    def library(self) -> str:
        return f"/usr/share/ansible:{self.base / 'library'}"

    @property
    def log_dir(self) -> Path:
        return self.base / "logs"

    @property
    def tmp(self) -> Path:
        return self.base / "tmp"

    def log_path(self) -> Path:
        return self.log_dir / f"run-{datetime.now():%y%m%d%H%M%S}.log"

    def playbook(self, name: str) -> Path:
        """Resolve a playbook by bare name, as `utils/pb <name>` takes it."""
        return self.playbooks / f"{name}.yml"

    # ── environment ───────────────────────────────────────────────────────────

    def overrides(self) -> dict[str, str]:
        """The ANSIBLE_* variables this repo's tooling defines.

        ANSIBLE_INVENTORY and ANSIBLE_LIBRARY are read by ansible-core itself.
        The rest are repo conventions consumed by the utils/ wrappers —
        ANSIBLE_HOSTS is the legacy alias still passed as `-i` by ar, reboot,
        and shutdown.
        """
        return {
            "ANSIBLE_BASE": str(self.base),
            "ANSIBLE_INVENTORY": self.inventory,
            "ANSIBLE_HOSTS": self.inventory,
            "ANSIBLE_LIBRARY": self.library,
            "ANSIBLE_ROLES": str(self.roles),
            "ANSIBLE_PLAYBOOKS": str(self.playbooks),
            "ANSIBLE_LOG_DIR": str(self.log_dir),
            "ANSIBLE_LOG": str(self.log_path()),
            "ANSIBLE_TMP": str(self.tmp),
            "ANSIBLE_FORCE_COLOR": "1",
        }

    def env(self) -> dict[str, str]:
        """Full environment for a child process."""
        return {**os.environ, **self.overrides()}

    def export_lines(self) -> str:
        """Shell `export` statements, for `eval` by utils/setup-env."""
        return "\n".join(
            f"export {k}={shlex.quote(v)}" for k, v in self.overrides().items()
        )

    def ensure_dirs(self) -> None:
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.tmp.mkdir(parents=True, exist_ok=True)
