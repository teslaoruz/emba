"""One line of news from each service that has a key in the system keyring.

    python status.py        (on a Python with `keyring`: Emba's venv)

Prints one JSON object per line: {"service", "state": "ok"|"warn"|"bad"|"busy", "title", "detail", "url"}.
Services without a key print nothing. A refused key or a network error prints one
line saying so, never the key.
"""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import keyring


def key(name):
    return keyring.get_password("emba", name) or ""


def call(url, token=None, headers=None, data=None, auth="Bearer"):
    h = {"Accept": "application/json", "User-Agent": "emba"}
    if token:
        h["Authorization"] = f"{auth} {token}"
    h.update(headers or {})
    body = json.dumps(data).encode() if data is not None else None
    if body:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=h, method="POST" if body else "GET")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())


def ago(ms):
    m = int((time.time() * 1000 - ms) / 60000)
    return f"{m}m ago" if m < 60 else f"{m // 60}h ago" if m < 1440 else f"{m // 1440}d ago"


def vercel(k):
    d = call("https://api.vercel.com/v6/deployments?limit=10", k).get("deployments") or []
    if not d:
        return {"state": "ok", "title": "Vercel", "detail": "no deployments yet", "url": "https://vercel.com/dashboard"}
    x = d[0]
    state = (x.get("state") or x.get("readyState") or "").upper()
    word = {"READY": "live", "ERROR": "failed", "BUILDING": "building", "QUEUED": "queued", "CANCELED": "cancelled"}.get(state, state.lower())
    return {"state": {"READY": "ok", "ERROR": "bad", "BUILDING": "busy", "QUEUED": "busy"}.get(state, "warn"),
            "title": f"Vercel · {x.get('name', '')}", "detail": f"{word} · {ago(x.get('created', 0))}",
            "url": f"https://{x['url']}" if x.get("url") else "https://vercel.com/dashboard"}


def stripe(k):
    start = int(time.mktime(time.localtime()[:3] + (0, 0, 0, 0, 0, -1)))  # local midnight
    q = urllib.parse.urlencode({"limit": 100, "created[gte]": start})
    charges = [c for c in call(f"https://api.stripe.com/v1/charges?{q}", k).get("data") or [] if c.get("paid") and c.get("status") == "succeeded"]
    totals = {}
    for c in charges:
        cur = c.get("currency", "").upper()
        totals[cur] = totals.get(cur, 0) + c.get("amount", 0) / 100
    money = " + ".join(f"{v:,.2f} {cur}" for cur, v in totals.items()) or "nothing yet"
    n = len(charges)
    return {"state": "ok", "title": "Stripe · today", "detail": f"{money} · {n} payment{'s' if n != 1 else ''}",
            "url": "https://dashboard.stripe.com/payments"}


def resend(k):
    emails = call("https://api.resend.com/emails", k).get("data") or []
    bad = [e for e in emails if e.get("last_event") in ("bounced", "complained", "failed")]
    return {"state": "bad" if bad else "ok", "title": "Resend",
            "detail": f"{len(emails)} recent email{'s' if len(emails) != 1 else ''}" + (f" · {len(bad)} bounced" if bad else ""),
            "url": "https://resend.com/emails"}


def calcom(k):
    r = call("https://api.cal.com/v2/bookings?status=upcoming&take=1", k, {"cal-api-version": "2024-08-13"})
    b = (r.get("data") or [None])[0]
    if not b:
        return {"state": "ok", "title": "Cal.com", "detail": "nothing booked", "url": "https://app.cal.com/bookings/upcoming"}
    start = b.get("start") or b.get("startTime") or ""
    when = start.replace("T", " ")[:16] if start else ""
    return {"state": "ok", "title": f"Cal.com · {b.get('title', 'next booking')}", "detail": when,
            "url": "https://app.cal.com/bookings/upcoming"}


def notion(k):
    r = call("https://api.notion.com/v1/search", k, {"Notion-Version": "2022-06-28"},
             {"sort": {"direction": "descending", "timestamp": "last_edited_time"}, "page_size": 1})
    page = (r.get("results") or [None])[0]
    if not page:
        return {"state": "ok", "title": "Notion", "detail": "no pages shared with Emba", "url": "https://www.notion.so"}
    title = ""
    for prop in (page.get("properties") or {}).values():
        if prop.get("type") == "title":
            title = "".join(t.get("plain_text", "") for t in prop.get("title") or [])
    return {"state": "ok", "title": f"Notion · {title or 'Untitled'}", "detail": "last edited " + (page.get("last_edited_time") or "")[:10],
            "url": page.get("url") or "https://www.notion.so"}


def n8n(k):
    base = key("n8n-url").rstrip("/")
    if not base:
        return None
    r = call(f"{base}/api/v1/executions?status=error&limit=20", headers={"X-N8N-API-KEY": k})
    failed = r.get("data") or []
    return {"state": "bad" if failed else "ok", "title": "n8n",
            "detail": f"{len(failed)} failed run{'s' if len(failed) != 1 else ''} recently" if failed else "no failed runs",
            "url": f"{base}/home/executions"}


SERVICES = {"vercel": vercel, "stripe": stripe, "resend": resend, "calcom": calcom, "notion": notion, "n8n": n8n}
NAMES = {"vercel": "Vercel", "stripe": "Stripe", "resend": "Resend", "calcom": "Cal.com", "notion": "Notion", "n8n": "n8n"}


def main():
    for name, fetch in SERVICES.items():
        k = key(name)
        if not k:
            continue
        try:
            line = fetch(k)
        except urllib.error.HTTPError as e:
            line = {"state": "bad", "title": NAMES[name], "detail": "key refused" if e.code in (401, 403) else f"error {e.code}", "url": ""}
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            line = {"state": "warn", "title": NAMES[name], "detail": "can't reach it right now", "url": ""}
        if line:
            line["service"] = name
            print(json.dumps(line), flush=True)


if __name__ == "__main__":
    main()
