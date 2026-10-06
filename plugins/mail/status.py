"""Unread mail for Emba, over IMAP with an app password (Gmail, Outlook,
Fastmail, iCloud...). Emba runs it every two minutes (plugin.json "poll").

Keyring (Settings → Integrations): "mail-host" (e.g. imap.gmail.com),
"mail-user" (your address), "mail" (an app password, not your real one).

    python status.py              prints JSON lines (see PLUGINS.md)
    python status.py --selftest

The inbox is opened read-only and headers are read with PEEK: nothing gets
marked as read. Only message numbers are remembered (~/.cache/emba/mail.json),
never senders or subjects.
"""
import email.header
import email.utils
import imaplib
import json
import os
import re
import ssl
import sys
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "emba" / "mail.json"


def secrets():
    import keyring
    return [keyring.get_password("emba", n) or "" for n in ("mail-host", "mail-user", "mail")]


def text(raw):
    """A header as plain text: =?utf-8?...?= decoded, whitespace folded."""
    parts = []
    for chunk, enc in email.header.decode_header(raw or ""):
        parts.append(chunk.decode(enc or "utf-8", "replace") if isinstance(chunk, bytes) else chunk)
    return re.sub(r"\s+", " ", "".join(parts)).strip()


def sender(raw):
    name, addr = email.utils.parseaddr(text(raw))
    return name or addr or "someone"


def news(before, validity, unseen):
    """Which unread messages are new since the last look. A new mailbox (or a
    first look) is not news: that's the backlog."""
    if not before or before.get("validity") != validity:
        return []
    old = set(before.get("unseen", []))
    return [u for u in unseen if u not in old and u > before.get("top", 0)]


def main():
    host, user, password = secrets()
    if not (host and user and password):
        return
    try:
        imap = imaplib.IMAP4_SSL(host.strip(), 993, ssl_context=ssl.create_default_context(), timeout=30)
        imap.login(user.strip(), password)
        typ, info = imap.select("INBOX", readonly=True)
        v = imap.response("UIDVALIDITY")[1][0]  # response() hands it over once: read it once
        validity = v.decode() if v else ""
        typ, found = imap.uid("SEARCH", None, "UNSEEN")
        unseen = sorted(int(x) for x in (found[0] or b"").split())
        latest = []
        for uid in unseen[-3:][::-1]:
            typ, msg = imap.uid("FETCH", str(uid), "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
            m = email.message_from_bytes(msg[0][1]) if msg and isinstance(msg[0], tuple) else {}
            latest.append({"uid": uid, "from": sender(m.get("From")), "subject": text(m.get("Subject"))[:100] or "(no subject)"})
        imap.logout()
    except (imaplib.IMAP4.error, OSError, ssl.SSLError, IndexError, ValueError) as e:
        refused = isinstance(e, imaplib.IMAP4.error) and "auth" in str(e).lower()
        print(json.dumps({"data": {"error": "The mail password was refused." if refused else "Can't reach your mail right now."}}), flush=True)
        return
    try:
        before = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        before = {}
    print(json.dumps({"data": {"unread": len(unseen), "latest": [{k: x[k] for k in ("from", "subject")} for x in latest]}}), flush=True)
    new = news(before, validity, unseen)
    if new:
        top = next((x for x in latest if x["uid"] == new[-1]), None)
        say = f"Mail from {top['from']}: {top['subject']}" if len(new) == 1 and top else f"{len(new)} new emails"
        print(json.dumps({"notice": say, "mood": ""}), flush=True)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps({"validity": validity, "unseen": unseen[-500:], "top": max(unseen + [before.get("top", 0)])}))


def selftest():
    assert text("=?utf-8?q?Caf=C3=A9_invoice?=") == "Café invoice"
    assert sender('"Ana Ruiz" <ana@example.com>') == "Ana Ruiz" and sender("bob@example.com") == "bob@example.com"
    assert news({}, "7", [1, 2]) == [], "the first look is the backlog, not news"
    b = {"validity": "7", "unseen": [1, 2], "top": 5}
    assert news(b, "7", [1, 2, 6, 7]) == [6, 7]
    assert news(b, "7", [2]) == [], "read elsewhere: nothing new"
    assert news(b, "8", [1, 2, 9]) == [], "mailbox rebuilt: start over quietly"
    assert news(b, "7", [3]) == [], "an old message marked unread again is not new mail"
    flow()
    print("ok")


def flow():
    """main() against a stand-in mail server: read-only, PEEK, a first look, then one new mail."""
    import io
    import tempfile
    from contextlib import redirect_stdout
    global CACHE, secrets
    calls = []

    class Fake:
        unseen = b"3 4"

        def __init__(self, *a, **k):
            pass

        def login(self, u, p):
            calls.append(("login", u))

        def select(self, box, readonly=False):
            calls.append(("select", box, readonly))
            return "OK", [b"4"]

        def response(self, code):
            return code, [b"77"]

        def uid(self, cmd, *args):
            calls.append((cmd, *args))
            if cmd == "SEARCH":
                return "OK", [Fake.unseen]
            return "OK", [(b"x", b"From: Ana <ana@x.org>\r\nSubject: Lunch?\r\n\r\n")]

        def logout(self):
            pass

    real, real_secrets, real_cache = imaplib.IMAP4_SSL, secrets, CACHE
    imaplib.IMAP4_SSL, secrets = Fake, lambda: ["imap.x.org", "me@x.org", "app-pass"]
    CACHE = Path(tempfile.mkdtemp()) / "mail.json"
    try:
        def run():
            buf = io.StringIO()
            with redirect_stdout(buf):
                main()
            return [json.loads(x) for x in buf.getvalue().splitlines()]
        first = run()
        assert first == [{"data": {"unread": 2, "latest": [{"from": "Ana", "subject": "Lunch?"}] * 2}}], first
        assert ("select", "INBOX", True) in calls, "opened read-only"
        assert all("PEEK" in c[-1] for c in calls if c[0] == "FETCH"), "headers peeked, nothing marked read"
        Fake.unseen = b"3 4 5"
        second = run()
        assert second[-1] == {"notice": "Mail from Ana: Lunch?", "mood": ""}, second
        assert "Lunch" not in CACHE.read_text(), "no subjects on disk"
    finally:
        imaplib.IMAP4_SSL, secrets, CACHE = real, real_secrets, real_cache


if __name__ == "__main__":
    selftest() if sys.argv[1:2] == ["--selftest"] else main()
