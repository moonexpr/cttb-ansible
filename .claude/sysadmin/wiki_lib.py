"""
MediaWiki API toolkit for wiki.cttb — stdlib only.

  WikiContext   static config; extends CttbContext for credentials + SSH
  WikiSession   auth state: cookie jar + CSRF token, HTTP helpers
  API module    stateless operations that take WikiSession or WikiContext
"""
from __future__ import annotations

import http.cookiejar
import json
import os
import re
import shlex
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from cttb_api import CttbContext


# ── Context ───────────────────────────────────────────────────────────────────

@dataclass
class WikiContext(CttbContext):
    api_url: str = "http://wiki.cttb/w/api.php"
    ssh_host: str = "wiki"
    wiki_pages_dir: Path = field(
        default_factory=lambda: Path(__file__).parent.parent / "wiki-pages"
    )

    @classmethod
    def default(cls) -> "WikiContext":
        return cls(
            api_url=os.environ.get("WIKI_API", "http://wiki.cttb/w/api.php"),
            ssh_host=os.environ.get("WIKI_SSH_HOST", "wiki"),
        )

    def title_to_filename(self, title: str) -> Path:
        fname = title.replace(" ", "_").replace(":", "_") + ".txt"
        return self.wiki_pages_dir / fname

    def maint_ssh(self, remote_cmd: str, *, stdin: str = None) -> None:
        self.ssh(self.ssh_host, remote_cmd, stdin=stdin)


# ── Session ───────────────────────────────────────────────────────────────────

class WikiSession:
    """Authenticated MediaWiki session.  Call login() before write operations."""

    def __init__(self, ctx: Optional[WikiContext] = None):
        self.ctx = ctx or WikiContext.default()
        self._jar = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self._jar)
        )
        self.csrf: Optional[str] = None

    # ── HTTP ─────────────────────────────────────────────────────────

    def get(self, **params) -> dict:
        params.setdefault("format", "json")
        url = f"{self.ctx.api_url}?{urllib.parse.urlencode(params)}"
        with self._opener.open(url) as r:
            return json.load(r)

    def post(self, **params) -> dict:
        params.setdefault("format", "json")
        data = urllib.parse.urlencode(params).encode()
        req = urllib.request.Request(self.ctx.api_url, data=data, method="POST")
        with self._opener.open(req) as r:
            return json.load(r)

    def post_multipart(self, fields: dict[str, str], files: dict[str, tuple[str, bytes]]) -> dict:
        boundary = uuid.uuid4().hex
        parts: list[bytes] = []
        for name, value in fields.items():
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
            )
        for name, (filename, data) in files.items():
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()
                + data + b"\r\n"
            )
        parts.append(f"--{boundary}--\r\n".encode())
        req = urllib.request.Request(
            self.ctx.api_url, data=b"".join(parts), method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with self._opener.open(req) as r:
            return json.load(r)

    # ── Auth ─────────────────────────────────────────────────────────

    def login(self) -> None:
        bot_user = self.ctx.credential("WIKI_CTTB_BOT_USER")
        bot_pass = self.ctx.credential("WIKI_CTTB_BOT_PASSWD")

        d = self.get(action="query", meta="tokens", type="login")
        login_token = d["query"]["tokens"]["logintoken"]

        # bot_pass is a Keychain credential (WIKI_CTTB_BOT_PASSWD), not a literal.
        # The trailing # ggignore silences a GitGuardian false positive on the
        # lgpassword= keyword (the MediaWiki API param name, not a real secret).
        d = self.post(action="login", lgname=bot_user, lgpassword=bot_pass, lgtoken=login_token)  # ggignore
        if d["login"]["result"] != "Success":
            raise RuntimeError(f"login failed: {d['login']['result']}")

        d = self.get(action="query", meta="tokens")
        self.csrf = d["query"]["tokens"]["csrftoken"]

    def require_csrf(self) -> str:
        if not self.csrf:
            raise RuntimeError("not authenticated — call session.login() first")
        return self.csrf


# ── API ───────────────────────────────────────────────────────────────────────

@dataclass
class ProbeResult:
    title: str
    exists: bool
    page_id: Optional[int] = None


def probe(session: WikiSession, titles: list[str]) -> list[ProbeResult]:
    results = []
    for title in titles:
        d = session.get(action="query", prop="info", formatversion="2", titles=title)
        page = d.get("query", {}).get("pages", [{}])[0]
        if page.get("missing"):
            results.append(ProbeResult(title=title, exists=False))
        else:
            results.append(ProbeResult(title=title, exists=True, page_id=page.get("pageid")))
    return results


def download(session: WikiSession, title: str) -> str:
    d = session.get(
        action="query", prop="revisions", rvprop="content",
        rvslots="main", formatversion="2", titles=title,
    )
    pages = d.get("query", {}).get("pages", [])
    if not pages:
        raise RuntimeError(f"{title}: no pages in response")
    page = pages[0]
    if page.get("missing"):
        raise RuntimeError(f"{title}: page does not exist")
    revs = page.get("revisions", [])
    if not revs or "slots" not in revs[0]:
        raise RuntimeError(f"{title}: no content in response")
    return revs[0]["slots"]["main"].get("content", "")


def edit(session: WikiSession, title: str, text: str, summary: str = "Automated edit") -> str:
    csrf = session.require_csrf()
    d = session.post(action="edit", title=title, token=csrf, summary=summary, text=text)
    return d.get("edit", {}).get("result", f"FAILED: {d}")


def purge(session: WikiSession, titles: list[str], force: bool = False) -> None:
    """Purge HTML cache via SSH maintenance script; --force also triggers API forcelinkupdate."""
    cmd = "sudo -u www-data php /var/www/html/w/maintenance/run.php purgeList"
    session.ctx.maint_ssh(cmd, stdin="\n".join(titles))
    if force:
        session.post(action="purge", forcelinkupdate="1", titles="|".join(titles))
        print(":: forcelinkupdate done")


def delete(session: WikiSession, title: str, reason: str) -> None:
    csrf = session.require_csrf()
    d = session.post(action="delete", title=title, reason=reason, token=csrf)
    if "error" in d:
        raise RuntimeError(f"{title}: {d['error']['info']}")
    print(f"{title}: deleted (logid {d.get('delete', {}).get('logid', '?')})")


def upload(session: WikiSession, path: Path, comment: str = "Uploaded via wiki tool") -> str:
    csrf = session.require_csrf()
    d = session.post_multipart(
        fields={"action": "upload", "filename": path.name, "comment": comment,
                "token": csrf, "format": "json", "ignorewarnings": "1"},
        files={"file": (path.name, path.read_bytes())},
    )
    return d.get("upload", {}).get("result", f"FAILED: {d}")


def maint(ctx: WikiContext, subcommand: str, *args: str) -> None:
    """Run maintenance/run.php on the wiki container via ssh."""
    remote_cmd = shlex.join([
        "sudo", "-u", "www-data", "php",
        "/var/www/html/w/maintenance/run.php",
        subcommand, *args,
    ])
    ctx.maint_ssh(remote_cmd)


# ── Audit drafts ──────────────────────────────────────────────────────────────

_NS_PREFIXES = ("IT_", "MediaWiki_", "Template_", "DRBU_", "DVGS_", "DVBS_", "CTTB_")


def _file_to_title(fname: str) -> Optional[str]:
    base = re.sub(r"\.txt$", "", fname)
    if base.startswith("_redirect_"):
        return None
    for px in _NS_PREFIXES:
        if base.startswith(px):
            ns = px.rstrip("_")
            return f"{ns}:{base[len(px):].replace('_', ' ')}"
    return base.replace("_", " ")


@dataclass
class AuditEntry:
    filename: str
    title: str
    status: str   # canonical | redirect | missing
    target: Optional[str] = None
    page_id: Optional[int] = None
    size: Optional[int] = None


def audit_drafts(session: WikiSession) -> list[AuditEntry]:
    entries = []
    for f in sorted(session.ctx.wiki_pages_dir.glob("*.txt")):
        title = _file_to_title(f.name)
        if title is None:
            continue
        d = session.get(
            action="query", prop="info|revisions", rvprop="content",
            rvslots="main", formatversion="2", titles=title,
        )
        page = d.get("query", {}).get("pages", [{}])[0]
        if page.get("missing"):
            entries.append(AuditEntry(filename=f.name, title=title, status="missing"))
            continue
        revs = page.get("revisions", [])
        content = revs[0]["slots"]["main"].get("content", "") if revs else ""
        if content.lstrip().upper().startswith("#REDIRECT"):
            m = re.search(r"\[\[([^\]]+)\]\]", content)
            entries.append(AuditEntry(
                filename=f.name, title=title, status="redirect",
                target=m.group(1) if m else "?",
            ))
        else:
            entries.append(AuditEntry(
                filename=f.name, title=title, status="canonical",
                page_id=page.get("pageid"), size=len(content),
            ))
    return entries
