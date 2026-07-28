"""
File-backed credential store — the headless fallback.

Reads ~/.config/cttb/secrets/<SERVICE>, one secret per file, first line only.

This is the path for machines with no usable credential store: a headless
server, a cron/agent run with no login session, or a bare WSL shell with no
D-Bus keyring.  It replaces the retired $CTTB_VAULT_PASS environment variable,
which leaked through `ps -E`, /proc/<pid>/environ, and every child process.

Create a credential with:

    mkdir -p ~/.config/cttb/secrets
    printf '%s' '<value>' > ~/.config/cttb/secrets/CTTB_VAULT_PASS
    chmod 600 ~/.config/cttb/secrets/CTTB_VAULT_PASS
"""
from __future__ import annotations

import stat
from pathlib import Path

from cttb_api import CredentialStore

_DEFAULT_DIR = Path.home() / ".config" / "cttb" / "secrets"


class FileStore(CredentialStore):
    def __init__(self, directory: Path | None = None) -> None:
        self.directory = directory or _DEFAULT_DIR

    def get(self, service: str) -> str:
        path = self.directory / service
        try:
            mode = path.stat().st_mode
        except OSError as exc:
            raise LookupError(f"credential {service!r} not found at {path}") from exc

        # Loud, not silent: a readable-by-others secret is a finding, not a miss.
        # PermissionError (not LookupError) so a ChainedStore cannot swallow it.
        if mode & (stat.S_IRWXG | stat.S_IRWXO):
            raise PermissionError(
                f"{path} is group- or world-accessible; run: chmod 600 {path}"
            )

        lines = path.read_text().splitlines()
        if not lines or not (secret := lines[0].strip()):
            raise LookupError(f"{path} is empty")
        return secret
