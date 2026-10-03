"""GitHub status for the folders Emba's sessions run in, through the `gh` CLI.

    python status.py DIR [DIR...]

Prints one JSON object per line, one per GitHub repository found:
{"repo", "branch", "ci": {"state", "name", "url"} | null, "pr": {"number", "title", "state", "review", "url"} | null}
Folders that aren't GitHub checkouts, or a missing or logged-out gh, print nothing.
"""
import json
import shutil
import subprocess
import sys


def gh(args, cwd):
    try:
        r = subprocess.run(["gh", *args], cwd=cwd, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except ValueError:
        return None


def git(args, cwd):
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def main(dirs):
    if not shutil.which("gh") or not shutil.which("git"):
        return
    seen = set()
    for d in dirs:
        top = git(["rev-parse", "--show-toplevel"], d)
        if not top or top in seen:
            continue
        seen.add(top)
        repo = gh(["repo", "view", "--json", "nameWithOwner"], top)
        if not repo:
            continue  # not on GitHub, or gh isn't logged in
        branch = git(["branch", "--show-current"], top)
        runs = gh(["run", "list", "--limit", "1", "--branch", branch, "--json", "status,conclusion,workflowName,url"], top) if branch else None
        ci = None
        if runs:
            r = runs[0]
            state = r.get("conclusion") or r.get("status") or ""  # success failure cancelled / in_progress queued
            ci = {"state": state, "name": r.get("workflowName", ""), "url": r.get("url", "")}
        pr = gh(["pr", "view", "--json", "number,title,state,reviewDecision,url"], top)
        if pr:
            pr = {"number": pr.get("number"), "title": pr.get("title", "")[:120], "state": pr.get("state", ""),
                  "review": pr.get("reviewDecision") or "", "url": pr.get("url", "")}
        print(json.dumps({"repo": repo["nameWithOwner"], "branch": branch, "ci": ci, "pr": pr or None}), flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
