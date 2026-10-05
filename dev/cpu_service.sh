#!/bin/sh
# CPU of the Emba you run (the systemd service's Quickshell), over N seconds.
#   sh dev/cpu_service.sh [SECONDS]
cd "$(dirname "$0")/.."
main=$(systemctl --user show -p MainPID --value emba)
qs=$(pgrep -P "$main" -x qs)
python3 dev/cpu.py "${qs:-$main}" "${1:-10}"
