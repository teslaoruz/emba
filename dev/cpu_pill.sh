#!/bin/sh
# CPU of the running Emba with two busy fake sessions (the breathing pill),
# measured twice after it settles.
#   sh dev/cpu_pill.sh
cd "$(dirname "$0")/.."
systemctl --user restart emba
sleep 25
python3 dev/fake.py start > /dev/null 2>&1
sleep 3
sh dev/cpu_service.sh 8
sh dev/cpu_service.sh 8
python3 dev/fake.py end > /dev/null 2>&1
