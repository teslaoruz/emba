#!/bin/sh
# A Claude Code AskUserQuestion through the real hook: picture of the island,
# then answer it from Emba and print what the hook gives back to Claude.
#   sh dev/question_test.sh
cd "$(dirname "$0")/.."
cat > /tmp/emba-question.json << 'EOF'
{"hook_event_name": "PermissionRequest", "session_id": "q1", "cwd": "/home/you/code/invoices",
 "tool_name": "AskUserQuestion", "tool_use_id": "toolu_q1",
 "tool_input": {"questions": [{"question": "Which database should the invoices service use?",
   "header": "Database", "multiSelect": false,
   "options": [{"label": "PostgreSQL", "description": "Relational, what the rest of the stack uses"},
               {"label": "SQLite", "description": "One file, nothing to run"}]}]}}
EOF
python3 hook/emba-hook < /tmp/emba-question.json > /tmp/emba-question.out &
sleep 1.6
python3 bin/emba snapshot "$PWD/dev/question.png"; sleep 0.6
python3 bin/emba answer SQLite
wait
echo "hook printed:"; cat /tmp/emba-question.out; echo
printf '{"hook_event_name":"SessionEnd","session_id":"q1"}' | python3 hook/emba-hook
