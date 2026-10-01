#!/bin/sh
# Restart emba, walk it through every view with fake events, and stitch the
# screenshots into dev/tour.png.
cd "$(dirname "$0")/.."
geo=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x + .width - 500),\(.y) 500x400"')
grab() { sleep "${2:-1.1}"; grim -g "$geo" "dev/t-$1.png"; }
ipc() { qs -p . ipc call emba "$@" > /dev/null; }

sh dev/run.sh
qs -p dev/backdrop.qml > /dev/null 2>&1 &
bd=$!
python3 dev/fake.py end 2>/dev/null
grab hidden 0.8
python3 dev/fake.py start;            grab compact
ipc toggle;                           grab overview
python3 dev/fake.py ask > dev/answer.txt &
                                      grab approval
ipc deny
python3 dev/fake.py done;             grab finished
ipc toggle; sleep 0.5
python3 dev/fake.py limit 30
python3 dev/fake.py limit 86;         grab limit
ipc toggle; sleep 0.5
ipc ask;                              grab ask
ipc toggle
python3 dev/fake.py end
kill $bd
wait
python3 dev/sheet.py dev/tour.png dev/t-hidden.png dev/t-compact.png dev/t-overview.png dev/t-approval.png dev/t-finished.png dev/t-limit.png dev/t-ask.png
echo "answer: $(cat dev/answer.txt)"
grep -iE "error|warn" dev/run.log | grep -vE "config.json|PeerClosed" | head
