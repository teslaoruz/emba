"""GitHub for Emba, through the `gh` CLI you're logged in with. Emba runs it
every minute (plugin.json "poll"), also while the island is closed.

    python status.py [DIR...]          folders: $EMBA_DIRS (one per line) or the arguments
    python status.py --selftest

Prints JSON lines:
  {"data": {"repos": [{"repo", "branch", "ci", "pr"}], "reviews": [{"repo", "number", "title", "url"}]}}
  {"notice": "...", "mood": "..."}   when a session branch's checks just finished, or
                                     someone just asked for your review
Remembers the last look in ~/.cache/emba/github.json to tell what changed.
A missing or logged-out gh prints nothing.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "emba" / "github.json"
RUNNING = ("in_progress", "queued", "pending", "waiting", "requested")


def gh(args, cwd=None):
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


def repo_status(top):
    repo = gh(["repo", "view", "--json", "nameWithOwner"], top)
    if not repo:
        return None  # not on GitHub, or gh isn't logged in
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
    return {"repo": repo["nameWithOwner"], "branch": branch, "ci": ci, "pr": pr or None}


def changes(before, repos, reviews):
    """Heads-ups for what changed since the last look: [(text, mood)]."""
    out = []
    for r in repos:
        key, now = f"{r['repo']}@{r['branch']}", (r.get("ci") or {}).get("state", "")
        was = before.get("ci", {}).get(key, "")
        name = r["repo"].split("/")[-1]
        if was in RUNNING and now == "failure":
            out.append((f"Checks failed on {name}", "annoyed"))
        elif was in RUNNING and now == "success":
            out.append((f"Checks passed on {name}", "happy"))
    seen = set(before.get("reviews", []))
    new = [x for x in reviews if x["url"] not in seen]
    if "reviews" in before and new:  # not on the very first look: those aren't news
        out.append((f"{new[0]['title'][:50]} wants your review" if len(new) == 1 else f"{len(new)} pull requests want your review", "surprised"))
    return out


def main(argv):
    if not shutil.which("gh") or not shutil.which("git"):
        return
    dirs = [d for d in (os.environ.get("EMBA_DIRS") or "").splitlines() if d] or argv
    repos, seen = [], set()
    for d in dirs:
        top = git(["rev-parse", "--show-toplevel"], d)
        if top and top not in seen:
            seen.add(top)
            r = repo_status(top)
            if r:
                repos.append(r)
    found = gh(["search", "prs", "--review-requested=@me", "--state=open", "--limit", "20",
                "--json", "number,title,url,repository"])
    if found is None and not repos:
        return  # logged out or offline: say nothing rather than "all clear"
    reviews = [{"repo": (x.get("repository") or {}).get("nameWithOwner", ""), "number": x.get("number"),
                "title": x.get("title", "")[:120], "url": x.get("url", "")} for x in found or []]
    try:
        before = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        before = {}
    print(json.dumps({"data": {"repos": repos, "reviews": reviews}}), flush=True)
    for text, mood in changes(before, repos, reviews):
        print(json.dumps({"notice": text, "mood": mood}), flush=True)
    ci = {**before.get("ci", {}), **{f"{r['repo']}@{r['branch']}": (r.get("ci") or {}).get("state", "") for r in repos}}
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps({"ci": ci, "reviews": [x["url"] for x in reviews] if found is not None else before.get("reviews", [])}))


def selftest():
    b = {"ci": {"me/shop@fix": "in_progress", "me/api@main": "queued"}, "reviews": ["u1"]}
    repos = [{"repo": "me/shop", "branch": "fix", "ci": {"state": "failure"}},
             {"repo": "me/api", "branch": "main", "ci": {"state": "success"}},
             {"repo": "me/web", "branch": "x", "ci": {"state": "failure"}}]  # never seen running: no news
    got = changes(b, repos, [{"url": "u1", "title": "old"}, {"url": "u2", "title": "Add login"}])
    assert got == [("Checks failed on shop", "annoyed"), ("Checks passed on api", "happy"),
                   ("Add login wants your review", "surprised")], got
    assert changes({}, repos, [{"url": "u2", "title": "x"}]) == [], "the first look is not news"
    print("ok")


if __name__ == "__main__":
    selftest() if sys.argv[1:2] == ["--selftest"] else main(sys.argv[1:])
