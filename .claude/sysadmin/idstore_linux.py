"""
Linux Secret Service credential store — libsecret / `secret-tool` implementation.

Requires: apt install libsecret-tools

Store a credential with:

    secret-tool store --label=CTTB_VAULT_PASS service CTTB_VAULT_PASS

Needs a running Secret Service provider (gnome-keyring, KeepassXC, …) reachable
over the session D-Bus.  On a headless box or a bare WSL shell there is no such
provider — use idstore_file.FileStore instead; cttb_api._detect_idstore() picks
between them automatically.
"""
from __future__ import annotations

import shutil
import subprocess

from cttb_api import CredentialStore


class SecretToolStore(CredentialStore):
    def get(self, service: str) -> str:
        if shutil.which("secret-tool") is None:
            raise LookupError(
                "secret-tool not installed (apt install libsecret-tools)"
            )
        try:
            r = subprocess.run(
                ["secret-tool", "lookup", "service", service],
                capture_output=True, text=True, check=True,
            )
        except subprocess.CalledProcessError as exc:
            raise LookupError(
                f"credential {service!r} not found in the Secret Service keyring"
            ) from exc
        # secret-tool exits 0 with empty stdout when the schema matches nothing.
        if not (secret := r.stdout.strip()):
            raise LookupError(
                f"credential {service!r} not found in the Secret Service keyring"
            )
        return secret
