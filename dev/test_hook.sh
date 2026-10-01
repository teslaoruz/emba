#!/bin/sh
# End-to-end check of hook/emba-hook against a running emba. Exits non-zero on failure.
cd "$(dirname "$0")/.."
H=hook/emba-hook
fail() { echo "FAIL: $*"; exit 1; }
ipc() { qs -p . ipc call emba "$@"; }

sh dev/run.sh > /dev/null
echo '{"hook_event_name":"SessionStart","session_id":"t-1","cwd":"/tmp/demo"}' | $H
ipc state | grep -q '"t-1"' || fail "SessionStart not seen"

req='{"hook_event_name":"PermissionRequest","session_id":"t-1","cwd":"/tmp/demo","tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_use_id":"toolu_1","permission_suggestions":[{"type":"addRules"}]}'

# allow from emba
(sleep 1; ipc allow > /dev/null) &
out=$(echo "$req" | $H); wait
echo "$out" | grep -q '"behavior": "allow"' || fail "allow: $out"

# deny from emba
(sleep 1; ipc deny > /dev/null) &
out=$(echo "$req" | sed 's/toolu_1/toolu_2/' | $H); wait
echo "$out" | grep -q '"behavior": "deny"' || fail "deny: $out"

# terminal answered first: next event cancels, hook prints nothing
(sleep 1; echo '{"hook_event_name":"PreToolUse","session_id":"t-1","tool_name":"Read","tool_input":{}}' | $H) &
out=$(echo "$req" | sed 's/toolu_1/toolu_3/' | $H); wait
[ -z "$out" ] || fail "cancel printed: $out"

# Codex: same protocol, argv-style command, no tool_use_id
echo '{"hook_event_name":"SessionStart","session_id":"cx","cwd":"/tmp/cx"}' | $H --agent codex
(sleep 1; ipc allow > /dev/null) &
out=$(echo '{"hook_event_name":"PermissionRequest","session_id":"cx","cwd":"/tmp/cx","tool_name":"Bash","tool_input":{"command":["rm","-rf","dist"]},"turn_id":"t1"}' | $H --agent codex); wait
echo "$out" | grep -q '"behavior": "allow"' || fail "codex allow: $out"
ipc state | grep -q '"agent":"codex"' || fail "codex session not tagged"

# Gemini: renamed events, must always print JSON, permission asks show as attention
out=$(echo '{"hook_event_name":"BeforeAgent","session_id":"gm","cwd":"/tmp/gm","prompt":"hi"}' | $H --agent gemini)
[ "$out" = "{}" ] || fail "gemini stdout: $out"
echo '{"hook_event_name":"Notification","session_id":"gm","cwd":"/tmp/gm","notification_type":"ToolPermission","message":"Allow shell?"}' | $H --agent gemini > /dev/null
ipc state | grep -q '"sid":"gemini-gm"[^}]*"state":"waiting"' || ipc state | grep -q '"state":"waiting"[^}]*"sid":"gemini-gm"' || fail "gemini attention not waiting: $(ipc state)"

# emba not running: instant, silent
sh dev/run.sh stop
start=$(date +%s%N)
out=$(echo "$req" | $H)
ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ -z "$out" ] || fail "no emba printed: $out"
[ $ms -lt 500 ] || fail "no emba took ${ms}ms"

# statusline passes the wrapped command's output through untouched
out=$(echo '{"rate_limits":{}}' | $H statusline 'echo wrapped-ok')
[ "$out" = "wrapped-ok" ] || fail "statusline: $out"

echo "all hook checks passed (no-emba exit ${ms}ms)"
