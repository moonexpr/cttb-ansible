"""
Shared CTTB infrastructure primitives.

  CredentialStore           ABC — implement .get(service) for a new platform
  get_idstore()             lazy singleton; auto-detects platform
  set_idstore(store)        override (testing or future Windows support)
  credential(service)       module-level shortcut → get_idstore().get()
  credential_or_env(s)      env var → store → '' shortcut
  ssh_exec(host, cmd, ...)  one-shot SSH command
  CttbContext               base class — .credential(), .credential_or_env(), .ssh()

Platform implementations (auto-detected via sys.platform)
  idstore_macos.py    MacOSKeychain           (macOS security CLI)
  idstore_windows.py  WindowsCredentialStore  (Windows Credential Manager, pywin32)
  idstore_linux.py    SecretToolStore         (libsecret / secret-tool)
  idstore_file.py     FileStore               (~/.config/cttb/secrets, mode 0600)

Every platform chains FileStore last, so headless boxes and agent runs with no
login session still resolve credentials.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from abc import ABC, abstractmethod


# ── Credential store abstraction ──────────────────────────────────────────────

class CredentialStore(ABC):
    """Platform-agnostic credential provider."""

    @abstractmethod
    def get(self, service: str) -> str:
        """Return the secret for *service*.  Raises LookupError if absent."""

    def get_or_env(self, service: str) -> str:
        """Read from env var first, then the store.  Returns '' if neither set."""
        if val := os.environ.get(service):
            return val
        try:
            return self.get(service)
        except LookupError:
            return ""


class ChainedStore(CredentialStore):
    """Try each store in order; first hit wins.

    Only a miss (LookupError) advances to the next store.  A misconfiguration
    such as a world-readable secret file raises PermissionError and propagates,
    rather than being silently masked by a later store in the chain.
    """

    def __init__(self, *stores: CredentialStore) -> None:
        self._stores = stores

    def get(self, service: str) -> str:
        for store in self._stores:
            try:
                return store.get(service)
            except LookupError:
                continue
        raise LookupError(
            f"credential {service!r} not found in any configured store "
            f"({', '.join(type(s).__name__ for s in self._stores)})"
        )


# ── Platform detection ────────────────────────────────────────────────────────

_idstore: CredentialStore | None = None


def _detect_idstore() -> CredentialStore:
    from idstore_file import FileStore

    if sys.platform == "darwin":
        from idstore_macos import MacOSKeychain
        return ChainedStore(MacOSKeychain(), FileStore())
    if sys.platform == "win32":
        from idstore_windows import WindowsCredentialStore
        return ChainedStore(WindowsCredentialStore(), FileStore())
    if sys.platform.startswith("linux"):
        # A Secret Service provider needs the session bus; WSL and headless
        # servers usually have neither, so fall through to the file store.
        if shutil.which("secret-tool") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            from idstore_linux import SecretToolStore
            return ChainedStore(SecretToolStore(), FileStore())
        return FileStore()
    raise RuntimeError(
        f"No built-in credential store for platform {sys.platform!r}. "
        "Call set_idstore() with a CredentialStore implementation before use."
    )


def get_idstore() -> CredentialStore:
    """Return the active credential store, detecting the platform on first call."""
    global _idstore
    if _idstore is None:
        _idstore = _detect_idstore()
    return _idstore


def set_idstore(store: CredentialStore) -> None:
    """Override the active store (for testing or non-macOS platforms)."""
    global _idstore
    _idstore = store


# ── Module-level shortcuts ────────────────────────────────────────────────────

def credential(service: str) -> str:
    """Read a credential from the active store.  Raises LookupError if absent."""
    return get_idstore().get(service)


def credential_or_env(service: str) -> str:
    """Read from env var first, then the store.  Returns '' if neither set."""
    return get_idstore().get_or_env(service)


# ── SSH ───────────────────────────────────────────────────────────────────────

def ssh_exec(
    host: str,
    remote_cmd: str,
    *,
    stdin: str | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    """Run a shell command on a remote host via SSH.

    stdout/stderr flow to the terminal.  Pass stdin= to pipe text to the
    remote command (e.g. title lists for purgeList).
    """
    return subprocess.run(
        ["ssh", host, remote_cmd],
        input=stdin, text=True, check=check,
    )


# ── Base context ──────────────────────────────────────────────────────────────

class CttbContext:
    """Base class for CTTB API contexts.  Provides credential lookup and SSH."""

    def credential(self, service: str) -> str:
        return get_idstore().get(service)

    def credential_or_env(self, service: str) -> str:
        return get_idstore().get_or_env(service)

    def ssh(
        self,
        host: str,
        remote_cmd: str,
        *,
        stdin: str | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        return ssh_exec(host, remote_cmd, stdin=stdin, check=check)
