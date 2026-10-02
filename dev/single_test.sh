#!/bin/sh
# One Emba at a time: a second copy must leave; a reload of the first must not.
#   sh dev/single_test.sh
cd "$(dirname "$0")/.."
sh dev/run.sh > /dev/null
first=$(cat dev/qs.pid)
qs -p . > dev/second.log 2>&1 &
second=$!
sleep 4
if kill -0 "$second" 2> /dev/null; then echo "FAIL: second copy still running"; kill "$second"; else echo "ok: second copy left"; fi
kill -0 "$first" 2> /dev/null && echo "ok: first still running" || echo "FAIL: first died"
touch App.qml
sleep 4
kill -0 "$first" 2> /dev/null && echo "ok: survived a reload" || echo "FAIL: reload killed it"
