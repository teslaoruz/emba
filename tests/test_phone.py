"""Phone notifications against a fake ntfy server (no phone, no network).

    python tests/test_phone.py
"""
import json
import os
import queue
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
TOPIC = "emba-test-topic"
published = []          # what phone.py posted
replies = queue.Queue()  # what a "tap" sends down the reply stream


class Ntfy(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        published.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")

    def do_GET(self):
        assert self.path.startswith(f"/{TOPIC}-r/json"), self.path
        self.send_response(200)
        self.end_headers()
        while True:
            body = replies.get()
            self.wfile.write((json.dumps({"id": "x", "event": "message", "message": body}) + "\n").encode())
            self.wfile.flush()


def check(ok, what):
    print(("ok    " if ok else "FAIL: ") + what)
    if not ok:
        if "tmp" in globals():  # the hidden Emba's own words
            print("\n".join(x for x in open(f"{tmp}/host.log").read().splitlines() if "window masks" not in x)[-1500:])
        sys.exit(1)


server = ThreadingHTTPServer(("127.0.0.1", 0), Ntfy)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = dict(os.environ, EMBA_NTFY=f"http://127.0.0.1:{server.server_port}", EMBA_PHONE_TOPIC=TOPIC, EMBA_PHONE_DELAY="0.3")
p = subprocess.Popen([sys.executable, str(APP / "phone" / "phone.py")], env=env, text=True,
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)


def send(m):
    p.stdin.write(json.dumps(m) + "\n")
    p.stdin.flush()


# answered at the desk before the delay: never sent
send({"ask": {"id": "r1", "nonce": "n1", "name": "notes", "tool": "Bash", "command": "ls"}})
send({"gone": "r1"})
time.sleep(0.8)
check(not published, "a request answered at the desk is not sent")

# still waiting: sent with Allow and Deny
send({"ask": {"id": "r2", "nonce": "n2", "name": "invoices", "tool": "Bash", "command": "rm -rf build"}})
time.sleep(0.8)
check(len(published) == 1, "a waiting request is sent")
n = published[0]
check(n["topic"] == TOPIC and "invoices" in n["title"] and "rm -rf build" in n["message"], "it says who and what")
labels = [a["label"] for a in n["actions"]]
check(labels == ["Allow", "Deny"], f"buttons: {labels}")
check(all(a["url"].endswith(f"/{TOPIC}-r") for a in n["actions"]), "buttons answer on the private reply topic")

# the tap on Deny comes back to Emba with the nonce
replies.put(n["actions"][1]["body"])
line = json.loads(p.stdout.readline())
check(line == {"id": "r2", "nonce": "n2", "behavior": "deny"}, f"tap comes back: {line}")

# a question: its answers are the buttons
send({"ask": {"id": "r3", "nonce": "n3", "name": "api", "command": "Which database?", "options": ["PostgreSQL", "SQLite"]}})
time.sleep(0.8)
q = published[-1]
check([a["label"] for a in q["actions"]] == ["PostgreSQL", "SQLite"], "question answers are buttons")
replies.put(q["actions"][1]["body"])
line = json.loads(p.stdout.readline())
check(line.get("answer") == "SQLite" and line.get("nonce") == "n3", "the picked answer comes back")

# junk on the reply topic is ignored
replies.put("not json")
replies.put(json.dumps({"id": "r9", "behavior": "rm -rf /"}))
send({"done": {"name": "notes", "text": "All done."}})
time.sleep(0.5)
check(published[-1]["title"] == "notes is done", "a finished session can be sent")
p.kill()
print("helper checks passed")

# ---- the whole way: hook -> Emba -> phone -> tap -> hook, on a hidden Emba ----
import tempfile  # noqa: E402

tmp = tempfile.mkdtemp()
os.makedirs(f"{tmp}/emba")
json.dump({"phone": True, "phoneDelay": 0.3, "phoneServer": env["EMBA_NTFY"], "plugins": []},
          open(f"{tmp}/emba/config.json", "w"))
henv = dict(env, XDG_CONFIG_HOME=tmp, EMBA_SOCKET=f"{tmp}/emba.sock", QT_QPA_PLATFORM="offscreen")
log = open(f"{tmp}/host.log", "w")
host = subprocess.Popen([sys.executable, str(APP / "desktop" / "host.py")], env=henv, stdout=log, stderr=log)
try:
    hook = [sys.executable, str(APP / "hook" / "emba-hook")]
    for _ in range(60):  # up, and its status (which python has keyring) known
        time.sleep(0.25)
        st = subprocess.run([sys.executable, str(APP / "bin" / "emba"), "state"], env=henv, capture_output=True, text=True).stdout
        if st.strip():
            break
    time.sleep(3)
    published.clear()
    subprocess.run(hook, env=henv, input=json.dumps({"hook_event_name": "SessionStart", "session_id": "p1", "cwd": "/home/you/code/shop"}), text=True, timeout=10)
    asking = subprocess.Popen(hook, env=henv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    asking.stdin.write(json.dumps({"hook_event_name": "PermissionRequest", "session_id": "p1", "cwd": "/home/you/code/shop",
                                   "tool_name": "Bash", "tool_use_id": "toolu_p1", "tool_input": {"command": "npm publish"}}))
    asking.stdin.close()
    for _ in range(40):
        time.sleep(0.25)
        if published:
            break
    check(bool(published) and "npm publish" in published[-1]["message"], "Emba sends a waiting request to the phone")
    allow = next(a for a in published[-1]["actions"] if a["label"] == "Allow")
    forged = dict(json.loads(allow["body"]), nonce="guess")
    replies.put(json.dumps(forged))
    time.sleep(1)
    check(asking.poll() is None, "a tap with the wrong nonce answers nothing")
    replies.put(allow["body"])
    out = asking.communicate(timeout=15)[0]
    check('"allow"' in out, f"the tap on Allow reaches the agent: {out.strip()[:80]}")
finally:
    subprocess.run([sys.executable, str(APP / "bin" / "emba"), "quit"], env=henv, capture_output=True)
    host.kill()
print("all phone checks passed (with Emba)")
