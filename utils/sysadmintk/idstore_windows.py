"""
Windows Credential Manager credential store — pywin32 implementation.

Requires: pip install pywin32

To activate, call at program startup:

    from idstore_windows import WindowsCredentialStore
    from cttb_api import set_idstore
    set_idstore(WindowsCredentialStore())

Credentials are stored under the target name "CTTB/<service>" (Generic type).
Add them with:

    cmdkey /generic:CTTB/WIKI_CTTB_BOT_USER /user:. /pass:<value>
    cmdkey /generic:CTTB/LDAP_USERNAME       /user:. /pass:<value>

Or via Settings → Credential Manager → Windows Credentials → Add a generic credential.
"""
from __future__ import annotations

import win32cred

from cttb_api import CredentialStore

_TARGET_PREFIX = "CTTB/"


class WindowsCredentialStore(CredentialStore):

    def get(self, service: str) -> str:
        target = _TARGET_PREFIX + service
        try:
            cred = win32cred.CredRead(target, win32cred.CRED_TYPE_GENERIC)
            return cred["CredentialBlob"].decode("utf-16-le")
        except Exception as exc:
            raise LookupError(
                f"credential {target!r} not found in Windows Credential Manager"
            ) from exc
