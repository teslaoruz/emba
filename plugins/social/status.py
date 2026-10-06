"""Mentions, replies and follows on Bluesky and Mastodon, for Emba. Emba runs
it every two minutes (plugin.json "poll"); either account may be missing.

Keyring (Settings → Integrations):
  "bluesky-handle" (you.bsky.social), "bluesky" (an app password, not your real one)
  "mastodon-url" (https://mastodon.social), "mastodon" (a token with read:notifications)

    python status.py              prints JSON lines (see PLUGINS.md)
    python status.py --selftest

Bluesky allows few logins a day, so its session tokens are kept (in the
keyring, "bluesky-session") and refreshed rather than logging in each time.
Only notification ids are remembered on disk (~/.cache/emba/social.json).
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "emba" / "social.json"
BSKY = "https://bsky.social/xrpc"
WHAT = {"mention": "mentioned you", "reply": "replied", "follow": "followed you", "quote": "quoted you",
        "like": "liked your post", "repost": "reposted you", "favourite": "liked your post", "reblog": "boosted you"}


def keyring():
    import keyring as k
    return k


def call(url, body=None, token=None, method=None):
    headers = {"Content-Type": "application/json", "User-Agent": "Emba"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers,
                                 method=method or ("POST" if body is not None else "GET"))
    return json.loads(urllib.request.urlopen(req, timeout=20).read() or b"{}")


def bluesky():
    """(unread count, newest unread [{who, what}]) or None."""
    k = keyring()
    handle, password = k.get_password("emba", "bluesky-handle"), k.get_password("emba", "bluesky")
    if not (handle and password):
        return None
    try:
        session = json.loads(k.get_password("emba", "bluesky-session") or "{}")
    except ValueError:
        session = {}

    def fetch(token):
        n = call(f"{BSKY}/app.bsky.notification.getUnreadCount", token=token).get("count", 0)
        items = call(f"{BSKY}/app.bsky.notification.listNotifications?limit=10", token=token).get("notifications", [])
        return n, [{"who": (x.get("author") or {}).get("displayName") or (x.get("author") or {}).get("handle", "someone"),
                    "what": WHAT.get(x.get("reason"), x.get("reason", "")), "id": x.get("uri", "")}
                   for x in items if not x.get("isRead")]

    for attempt in ("access", "refresh", "login"):
        try:
            if attempt == "refresh":
                if not session.get("refreshJwt"):
                    continue
                session = call(f"{BSKY}/com.atproto.server.refreshSession", token=session["refreshJwt"], method="POST")
            elif attempt == "login":
                session = call(f"{BSKY}/com.atproto.server.createSession", {"identifier": handle.strip(), "password": password})
            elif not session.get("accessJwt"):
                continue
            result = fetch(session["accessJwt"])
            if attempt != "access":
                k.set_password("emba", "bluesky-session", json.dumps({x: session[x] for x in ("accessJwt", "refreshJwt")}))
            return result
        except urllib.error.HTTPError as e:
            if attempt == "login":
                return ("refused" if e.code in (400, 401) else None), []
        except (urllib.error.URLError, OSError, ValueError, KeyError):
            return None
    return None


def mastodon(since):
    """(new notifications [{who, what, id}], newest id) or None."""
    k = keyring()
    url, token = k.get_password("emba", "mastodon-url"), k.get_password("emba", "mastodon")
    if not (url and token) or not url.strip().startswith("https://"):
        return None
    q = urllib.parse.urlencode({"limit": 15, **({"since_id": since} if since else {})})
    try:
        items = call(f"{url.strip().rstrip('/')}/api/v1/notifications?{q}", token=token.strip())
    except urllib.error.HTTPError as e:
        return ("refused" if e.code in (401, 403) else None), since
    except (urllib.error.URLError, OSError, ValueError):
        return None
    new = [{"who": (x.get("account") or {}).get("display_name") or (x.get("account") or {}).get("acct", "someone"),
            "what": WHAT.get(x.get("type"), x.get("type", "")), "id": x.get("id", "")} for x in items]
    return new, (items[0]["id"] if items else since)


def heads_up(site, new):
    if not new:
        return None
    if len(new) == 1:
        return f"{new[0]['who']} {new[0]['what']} on {site}"
    return f"{len(new)} new on {site}"


def main():
    try:
        before = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        before = {}
    data, notices, after = {}, [], dict(before)
    b = bluesky()
    if b:
        count, items = b
        if count == "refused":
            data["bluesky"] = {"error": "Bluesky refused the app password."}
        else:
            data["bluesky"] = {"unread": count, "latest": items[:3]}
            seen = set(before.get("bsky", []))
            new = [x for x in items if x["id"] not in seen]
            if "bsky" in before:  # the first look is the backlog
                notices.append(heads_up("Bluesky", new))
            after["bsky"] = [x["id"] for x in items][:50]
    m = mastodon(before.get("masto"))
    if m:
        new, top = m
        if new == "refused":
            data["mastodon"] = {"error": "Mastodon refused the token."}
        else:
            data["mastodon"] = {"new": len(new) if "masto" in before else 0, "latest": new[:3]}
            if "masto" in before:
                notices.append(heads_up("Mastodon", new))
            after["masto"] = top or before.get("masto") or ""
    if not data:
        return
    print(json.dumps({"data": data}), flush=True)
    for n in filter(None, notices):
        print(json.dumps({"notice": n, "mood": "love"}), flush=True)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(after))


def selftest():
    assert heads_up("Bluesky", []) is None
    assert heads_up("Bluesky", [{"who": "Ana", "what": WHAT["reply"]}]) == "Ana replied on Bluesky"
    assert heads_up("Mastodon", [{}, {}]) == "2 new on Mastodon"
    print("ok")


if __name__ == "__main__":
    selftest() if sys.argv[1:2] == ["--selftest"] else main()
