"""Chat with Google's Gemini models, with the key from the system keyring (plain HTTP, stdlib only).

    python google_chat.py MODEL TEXT        $EMBA_TURNS: earlier [{"q", "a"}] of this chat
    python google_chat.py --models

Prints {"d": "..."} lines as the answer streams, then {"done": true}, or {"error": "..."}.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

import keyring

API = "https://generativelanguage.googleapis.com/v1beta"


def out(**kw):
    print(json.dumps(kw), flush=True)


def request(path, body=None):
    key = keyring.get_password("emba", "google") or ""
    if not key:
        out(error="No Google AI key yet: add one in Settings → Integrations.")
        sys.exit(1)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method="POST" if data else "GET",
                                 headers={"x-goog-api-key": key, "Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=60)


def main(argv):
    try:
        if argv[:1] == ["--models"]:
            models = json.loads(request("/models?pageSize=200").read()).get("models") or []
            print(json.dumps([m["name"].removeprefix("models/") for m in models
                              if "generateContent" in (m.get("supportedGenerationMethods") or [])]))
            return
        model, text = argv[0], argv[1]
        if not model:
            out(error="Pick a Gemini model first: click the model name above the box.")
            return
        contents = []
        for t in json.loads(os.environ.get("EMBA_TURNS") or "[]")[-20:]:
            contents += [{"role": "user", "parts": [{"text": t["q"]}]}, {"role": "model", "parts": [{"text": t["a"]}]}]
        contents.append({"role": "user", "parts": [{"text": text}]})
        body = {"contents": contents,
                "systemInstruction": {"parts": [{"text": "You are Emba, a small helper in the corner of the screen. Answer briefly and plainly."}]}}
        path = f"/models/{urllib.parse.quote(model)}:streamGenerateContent?alt=sse"
        with request(path, body) as r:
            for raw in r:
                line = raw.decode().strip()
                if not line.startswith("data: "):
                    continue
                for cand in json.loads(line[6:]).get("candidates") or []:
                    for part in (cand.get("content") or {}).get("parts") or []:
                        if part.get("text"):
                            out(d=part["text"])
        out(done=True)
    except urllib.error.HTTPError as e:
        out(error="The Google AI key was refused." if e.code in (400, 401, 403) else f"Google said: error {e.code}")
    except (urllib.error.URLError, TimeoutError, OSError):
        out(error="Can't reach Google AI right now.")


if __name__ == "__main__":
    main(sys.argv[1:])
