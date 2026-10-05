#!/bin/sh
# dev/openclose.sh on a separate Emba with no sessions (it hides fully when
# closed): the service pauses meanwhile, so the two don't overlap.
#   sh dev/openclose_bare.sh [ROUNDS]
cd "$(dirname "$0")/.."
systemctl --user stop emba
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-bare.sock"
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{"plugins": []}' > "$T/emba/config.json"
XDG_CONFIG_HOME=$T qs -p . > /dev/null 2>&1 &
sleep 5
sh dev/openclose.sh "${1:-2}"
python3 bin/emba quit > /dev/null 2>&1
systemctl --user start emba
