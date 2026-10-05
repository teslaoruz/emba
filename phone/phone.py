"""Emba on your phone, through ntfy (https://ntfy.sh, or your own server).

When an agent has waited a while for you, a notification goes to your phone
with buttons. A tap posts the answer to a second, private topic; this helper
listens there and hands the answer back to Emba.

    python phone.py           Emba writes JSON lines to stdin, reads answers from stdout
    python phone.py test      send one test notification

stdin  {"ask": {"id", "nonce", "name", "agent", "tool", "command", "options"}}
       {"gone": "<id>"}                    answered at the desk: don't send it
       {"done": {"name", "text"}}          a session finished (sent at once)
stdout {"id", "nonce", "behavior": "allow"|"deny", "answer"?}

The topic is a long random name kept in the system keyring ("phone"); it is
the only thing that keeps others out, so it never goes in a file or argv.
Every request also carries a one-time nonce that Emba checks, so a stale or
forged tap answers nothing. $EMBA_NTFY: the server, $EMBA_PHONE_DELAY: seconds
a request waits before it goes to the phone.
"""
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request


SERVER = (os.environ.get("EMBA_NTFY") or "https://ntfy.sh").rstrip("/")
DELAY = float(os.environ.get("EMBA_PHONE_DELAY") or 20)
lock = threading.Lock()
waiting = {}  # id -> Timer


def say(**kw):
    with lock:
        print(json.dumps(kw), flush=True)


def topic():
    # $EMBA_PHONE_TOPIC only for tests (tests/test_phone.py): Emba itself uses the keyring
    t = os.environ.get("EMBA_PHONE_TOPIC")
    if not t:
        import keyring  # in Emba's venv (bin/emba installs it with the first key)
        t = keyring.get_password("emba", "phone") or ""
    if not t:
        sys.exit("no phone topic yet: run `emba phone setup`")
    return t


def post(body):
    """Publish one notification (ntfy's JSON form: topic, title, message, actions)."""
    req = urllib.request.Request(SERVER, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=20).read()
    except (urllib.error.URLError, OSError):
        pass  # the phone misses this one; the desk still has it


def reply(t, label, answer):
    # A tap on the phone posts this to the reply topic; listen() reads it back.
    return {"action": "http", "label": label, "url": f"{SERVER}/{t}-r", "method": "POST",
            "body": json.dumps(answer), "clear": True}


def send_ask(t, req):
    rid, nonce = req["id"], req["nonce"]
    options = req.get("options") or []
    if options:  # a question: up to three answers fit on a notification
        actions = [reply(t, o[:40], {"id": rid, "nonce": nonce, "behavior": "allow", "answer": o}) for o in options[:3]]
        message = req.get("command") or "has a question"
    else:
        actions = [reply(t, "Allow", {"id": rid, "nonce": nonce, "behavior": "allow"}),
                   reply(t, "Deny", {"id": rid, "nonce": nonce, "behavior": "deny"})]
        message = f"{req.get('tool') or 'wants to'}: {req.get('command') or ''}".strip(": ")
    post({"topic": t, "title": f"{req.get('name') or 'An agent'} needs you", "message": message[:300],
          "tags": ["red_circle"], "priority": 4, "actions": actions})


def listen(t):
    """Follow the reply topic for good (ntfy streams one JSON object per line)."""
    since = str(int(time.time()))  # only answers from now on
    while True:
        try:
            with urllib.request.urlopen(f"{SERVER}/{t}-r/json?since={since}", timeout=90) as r:
                for raw in r:
                    m = json.loads(raw)
                    since = m.get("id") or since
                    if m.get("event") != "message":
                        continue
                    try:
                        a = json.loads(m.get("message") or "")
                    except ValueError:
                        continue
                    if isinstance(a, dict) and a.get("behavior") in ("allow", "deny"):
                        say(**{k: a[k] for k in ("id", "nonce", "behavior", "answer") if k in a})
        except (urllib.error.URLError, OSError, ValueError):
            time.sleep(5)  # offline or the server hung up: try again


def follow_parent():
    # leave with Emba (it may be killed without closing stdin)
    parent = os.getppid()
    while True:
        time.sleep(2)
        if os.getppid() != parent:
            os._exit(0)


def main(argv):
    t = topic()
    if argv[:1] == ["test"]:
        post({"topic": t, "title": "Emba", "message": "Hi from Emba. Requests that wait for you will show up here.",
              "tags": ["wave"]})
        return
    threading.Thread(target=listen, args=(t,), daemon=True).start()
    threading.Thread(target=follow_parent, daemon=True).start()
    for line in sys.stdin:
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if "ask" in m and isinstance(m["ask"], dict) and m["ask"].get("id") and m["ask"].get("nonce"):
            req = m["ask"]
            timer = threading.Timer(DELAY, lambda req=req: (waiting.pop(req["id"], None), send_ask(t, req)))
            timer.daemon = True
            waiting[req["id"]] = timer
            timer.start()
        elif "gone" in m:
            timer = waiting.pop(m["gone"], None)
            if timer:
                timer.cancel()
        elif "done" in m and isinstance(m["done"], dict):
            d = m["done"]
            post({"topic": t, "title": f"{d.get('name') or 'An agent'} is done", "message": (d.get("text") or "Finished.")[:300],
                  "tags": ["white_check_mark"]})


if __name__ == "__main__":
    main(sys.argv[1:])
