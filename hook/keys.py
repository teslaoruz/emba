"""API keys for Emba's integrations, kept in the system keyring (macOS Keychain,
Windows Credential Manager, the Secret Service on Linux), never in a file.

    python keys.py set NAME        the key comes from $EMBA_KEY (never the command line)
    python keys.py delete NAME
    python keys.py list            JSON {name: true} for every known name that has a key
    python keys.py get NAME        prints the key (for Emba's own helpers only)
"""
import json
import os
import sys

SERVICE = "emba"
NAMES = ["vercel", "stripe", "resend", "calcom", "notion", "n8n", "n8n-url", "anthropic", "openai", "google", "phone"]


def keyring():
    import keyring as k  # installed into Emba's venv on first use (see bin/emba)
    return k


def main(argv):
    op = argv[0] if argv else ""
    name = argv[1] if len(argv) > 1 else ""
    if op == "list":
        k = keyring()
        print(json.dumps({n: True for n in NAMES if k.get_password(SERVICE, n)}))
    elif op in ("set", "get", "delete") and name in NAMES:
        k = keyring()
        if op == "set":
            value = os.environ.get("EMBA_KEY", "").strip()
            if not value:
                sys.exit("no key given")
            k.set_password(SERVICE, name, value)
        elif op == "get":
            print(k.get_password(SERVICE, name) or "")
        else:
            try:
                k.delete_password(SERVICE, name)
            except Exception:
                pass  # already gone
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
