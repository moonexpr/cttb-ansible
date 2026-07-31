"""
macOS Keychain credential store.

Implements CredentialStore using the macOS `security` CLI.
"""
from __future__ import annotations

import os
import subprocess

from cttb_api import CredentialStore


class MacOSKeychain(CredentialStore):
    def get(self, service: str) -> str:
        try:
            r = subprocess.run(
                ["security", "find-generic-password",
                 "-a", os.environ.get("USER", ""), "-s", service, "-w"],
                capture_output=True, text=True, check=True,
            )
            return r.stdout.strip()
        except subprocess.CalledProcessError:
            raise LookupError(f"credential {service!r} not found in macOS Keychain")
