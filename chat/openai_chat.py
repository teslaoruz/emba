"""Chat with OpenAI models, with the key from the system keyring (plain HTTP, stdlib only).

    python openai_chat.py MODEL TEXT        $EMBA_TURNS: earlier [{"q", "a"}] of this chat
    python openai_chat.py --models

Prints {"d": "..."} lines as the answer streams, then {"done": true}, or {"error": "..."}.
"""
import json
import os
import sys
import urllib.error
import urllib.request

import keyring

API = "https://api.openai.com/v1"


def out(**kw):
    print(json.dumps(kw), flush=True)


def request(path, body=None):
    key = keyring.get_password("emba", "openai") or ""
    if not key:
        out(error="No OpenAI key yet: add one in Settings → Integrations.")
        sys.exit(1)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method="POST" if data else "GET",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=60)


def main(argv):
    try:
        if argv[:1] == ["--models"]:
            models = json.loads(request("/models").read()).get("data") or []
            print(json.dumps(sorted((m["id"] for m in models if m["id"].startswith(("gpt-", "o"))), reverse=True)))
            return
        model, text = argv[0], argv[1]
        if not model:
            out(error="Pick an OpenAI model first: click the model name above the box.")
            return
        messages = [{"role": "system", "content": "You are Emba, a small helper in the corner of the screen. Answer briefly and plainly."}]
        for t in json.loads(os.environ.get("EMBA_TURNS") or "[]")[-20:]:
            messages += [{"role": "user", "content": t["q"]}, {"role": "assistant", "content": t["a"]}]
        messages.append({"role": "user", "content": text})
        with request("/chat/completions", {"model": model, "messages": messages, "stream": True}) as r:
            for raw in r:
                line = raw.decode().strip()
                if not line.startswith("data: ") or line == "data: [DONE]":
                    continue
                choice = (json.loads(line[6:]).get("choices") or [{}])[0]
                piece = (choice.get("delta") or {}).get("content")
                if piece:
                    out(d=piece)
        out(done=True)
    except urllib.error.HTTPError as e:
        out(error="The OpenAI key was refused." if e.code in (401, 403) else f"OpenAI said: error {e.code}")
    except (urllib.error.URLError, TimeoutError, OSError):
        out(error="Can't reach OpenAI right now.")


if __name__ == "__main__":
    main(sys.argv[1:])
