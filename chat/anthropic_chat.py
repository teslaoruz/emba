"""Chat with Claude through the Anthropic API, with the key from the system keyring.

    python anthropic_chat.py MODEL TEXT        $EMBA_TURNS: earlier [{"q", "a"}] of this chat
    python anthropic_chat.py --models          the models this key can use (JSON list)

Prints one JSON line per piece of the answer as it streams: {"d": "..."}, then
{"done": true}; a problem prints {"error": "..."} instead. Needs `anthropic` and
`keyring` in Emba's venv (bin/emba installs them when the key is saved).
"""
import json
import os
import sys

import anthropic
import keyring

DEFAULT_MODEL = "claude-opus-5-5"


def out(**kw):
    print(json.dumps(kw), flush=True)


def client():
    key = keyring.get_password("emba", "anthropic") or ""
    if not key:
        out(error="No Anthropic key yet: add one in Settings → Integrations.")
        sys.exit(1)
    return anthropic.Anthropic(api_key=key)


def main(argv):
    if argv[:1] == ["--models"]:
        print(json.dumps([m.id for m in client().models.list()]))
        return
    model = argv[0] or DEFAULT_MODEL
    text = argv[1]
    messages = []
    for t in json.loads(os.environ.get("EMBA_TURNS") or "[]")[-20:]:
        messages += [{"role": "user", "content": t["q"]}, {"role": "assistant", "content": t["a"]}]
    messages.append({"role": "user", "content": text})
    try:
        with client().beta.messages.stream(
            model=model,
            max_tokens=16000,
            system="You are Emba, a small helper in the corner of the screen. Answer briefly and plainly.",
            messages=messages,
            # if a request is declined, the API retries it on a suitable model by itself
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        ) as stream:
            for piece in stream.text_stream:
                out(d=piece)
            final = stream.get_final_message()
        if final.stop_reason == "refusal":
            out(error="Claude declined to answer that.")
        else:
            out(done=True)
    except anthropic.AuthenticationError:
        out(error="The Anthropic key was refused.")
    except anthropic.NotFoundError:
        out(error=f"There's no model called {model}.")
    except anthropic.RateLimitError:
        out(error="Too many requests right now; try again in a minute.")
    except anthropic.APIStatusError as e:
        out(error=f"Anthropic said: {e.message}")
    except anthropic.APIConnectionError:
        out(error="Can't reach Anthropic right now.")


if __name__ == "__main__":
    main(sys.argv[1:])
