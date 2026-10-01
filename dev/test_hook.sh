#!/bin/sh
# End-to-end check of hook/perch-hook against a running perch. Exits non-zero on failure.
cd "$(dirname "$0")/.."
H=hook/perch-hook
fail() { echo "FAIL: $*"; exit 1; }
ipc() { qs -p . ipc call perch "$@"; }

sh dev/run.sh > /dev/null
echo '{"hook_event_name":"SessionStart","session_id":"t-1","cwd":"/tmp/demo"}' | $H
ipc state | grep -q '"t-1"' || fail "SessionStart not seen"

req='{"hook_event_name":"PermissionRequest","session_id":"t-1","cwd":"/tmp/demo","tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_use_id":"toolu_1","permission_suggestions":[{"type":"addRules"}]}'

# allow from perch
(sleep 1; ipc allow > /dev/null) &
out=$(echo "$req" | $H); wait
echo "$out" | grep -q '"behavior": "allow"' || fail "allow: $out"

# deny from perch
(sleep 1; ipc deny > /dev/null) &
out=$(echo "$req" | sed 's/toolu_1/toolu_2/' | $H); wait
echo "$out" | grep -q '"behavior": "deny"' || fail "deny: $out"

# terminal answered first: next event cancels, hook prints nothing
(sleep 1; echo '{"hook_event_name":"PreToolUse","session_id":"t-1","tool_name":"Read","tool_input":{}}' | $H) &
out=$(echo "$req" | sed 's/toolu_1/toolu_3/' | $H); wait
[ -z "$out" ] || fail "cancel printed: $out"

# perch not running: instant, silent
sh dev/run.sh stop
start=$(date +%s%N)
out=$(echo "$req" | $H)
ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ -z "$out" ] || fail "no perch printed: $out"
[ $ms -lt 500 ] || fail "no perch took ${ms}ms"

# statusline passes the wrapped command's output through untouched
out=$(echo '{"rate_limits":{}}' | $H statusline 'echo wrapped-ok')
[ "$out" = "wrapped-ok" ] || fail "statusline: $out"

echo "all hook checks passed (no-perch exit ${ms}ms)"
