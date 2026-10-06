"""Your calendar in Emba, from its private calendar link (ICS): the next events
today, and a heads-up a few minutes before one starts. Google, Outlook and
iCloud all give such a link; it's kept in the system keyring as "calendar".
Emba runs this every minute (plugin.json "poll").

    python status.py              prints JSON lines (see PLUGINS.md)
    python status.py --selftest

Needs `recurring-ical-events` in Emba's venv (installed when the link is saved).
"""
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "emba" / "calendar"
SOON = 5  # minutes before an event that Emba says so


def link():
    import keyring
    url = (keyring.get_password("emba", "calendar") or "").strip()
    return "https://" + url[len("webcal://"):] if url.startswith("webcal://") else url


def fetch(url):
    """The calendar file, re-downloaded at most every 10 minutes (they're big and change rarely)."""
    CACHE.mkdir(parents=True, exist_ok=True)
    ics = CACHE / "calendar.ics"
    if ics.exists() and (dt.datetime.now().timestamp() - ics.stat().st_mtime) < 600:
        return ics.read_bytes()
    try:
        data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Emba"}), timeout=30).read()
    except (urllib.error.URLError, OSError, ValueError):
        return ics.read_bytes() if ics.exists() else None  # offline: the last copy
    ics.write_bytes(data)
    os.chmod(ics, 0o600)  # your meetings: yours only
    return data


def upcoming(data, now, hours=12):
    """Events from now to `hours` ahead (recurrences and time zones resolved), soonest first."""
    import icalendar
    import recurring_ical_events
    cal = icalendar.Calendar.from_ical(data)
    out = []
    for ev in recurring_ical_events.of(cal).between(now - dt.timedelta(minutes=1), now + dt.timedelta(hours=hours)):
        start = ev.get("DTSTART").dt
        if not isinstance(start, dt.datetime):
            continue  # all-day: not a meeting to be late for
        start = start.astimezone() if start.tzinfo else start.replace(tzinfo=now.tzinfo)
        if start < now - dt.timedelta(minutes=1):
            continue  # already going
        if str(ev.get("STATUS", "")).upper() == "CANCELLED":
            continue
        out.append({"title": str(ev.get("SUMMARY", "Event"))[:80], "start": start.isoformat(),
                    "where": str(ev.get("LOCATION", ""))[:80], "uid": str(ev.get("UID", "")) + start.isoformat()})
    return sorted(out, key=lambda e: e["start"])


def main():
    url = link()
    if not url.startswith("https://"):
        return  # no link yet, or not an https one: nothing to say
    data = fetch(url)
    if not data:
        return
    now = dt.datetime.now().astimezone()
    try:
        events = upcoming(data, now)
    except Exception:  # a calendar file this can't read: stay quiet rather than crash every minute
        return
    print(json.dumps({"data": {"events": events[:5]}}), flush=True)
    told = CACHE / "told.json"
    try:
        seen = set(json.loads(told.read_text()))
    except (OSError, ValueError):
        seen = set()
    for e in events:
        mins = (dt.datetime.fromisoformat(e["start"]) - now).total_seconds() / 60
        if mins <= SOON and e["uid"] not in seen:
            print(json.dumps({"notice": f"{e['title']} in {max(0, round(mins))} min" if mins >= 1 else f"{e['title']} now",
                              "mood": "surprised"}), flush=True)
            seen.add(e["uid"])
    told.write_text(json.dumps(sorted(seen)[-200:]))


def selftest():
    tz = dt.timezone(dt.timedelta(hours=5))
    now = dt.datetime(2026, 10, 6, 9, 0, tzinfo=tz)
    ics = b"""BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:standup
DTSTART;TZID=Asia/Karachi:20260901T093000
DTEND;TZID=Asia/Karachi:20260901T094500
RRULE:FREQ=DAILY
SUMMARY:Standup
END:VEVENT
BEGIN:VEVENT
UID:gone
DTSTART:20261006T060000Z
SUMMARY:Cancelled one
STATUS:CANCELLED
END:VEVENT
BEGIN:VEVENT
UID:allday
DTSTART;VALUE=DATE:20261006
SUMMARY:Holiday
END:VEVENT
BEGIN:VEVENT
UID:review
DTSTART:20261006T070000Z
SUMMARY:Design review
LOCATION:Room 2
END:VEVENT
END:VCALENDAR
"""
    got = upcoming(ics, now)
    assert [e["title"] for e in got] == ["Standup", "Design review"], got   # repeat, time zone, order
    assert got[0]["start"].startswith("2026-10-06T09:30") and got[1]["where"] == "Room 2", got
    print("ok")


if __name__ == "__main__":
    selftest() if sys.argv[1:2] == ["--selftest"] else main()
