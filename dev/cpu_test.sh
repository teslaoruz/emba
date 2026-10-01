#!/bin/sh
# CPU of a separate Emba (own socket and settings) in each state.
#   sh dev/cpu_test.sh
cd "$(dirname "$0")/.."
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{}' > "$T/emba/config.json"
export XDG_CONFIG_HOME=$T EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-cpu.sock"
qs -p . > dev/cpu.log 2>&1 &
pid=$!
sleep 4
printf 'hidden, nothing running: '; python3 dev/cpu.py $pid 8
python3 dev/fake.py start; sleep 1
printf 'small pill, busy:        '; python3 dev/cpu.py $pid 8
python3 bin/emba open > /dev/null; sleep 1
printf 'open:                    '; python3 dev/cpu.py $pid 8
python3 bin/emba close > /dev/null; python3 dev/fake.py end; sleep 2
printf 'hidden again:            '; python3 dev/cpu.py $pid 8
kill $pid
