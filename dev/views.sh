#!/bin/sh
# Pictures of the main views straight from the island (windows on top don't matter).
#   sh dev/views.sh   -> dev/views.png
cd "$(dirname "$0")/.."
o=dev/v; rm -rf $o; mkdir -p $o
snap() { sleep "${2:-1.3}"; python3 bin/emba snapshot "$PWD/$o/$1.png" > /dev/null; sleep 0.5; }
[ -n "$EMBA_SOCKET" ] || sh dev/run.sh   # under dev/offscreen.sh it is already up
python3 bin/emba open > /dev/null;                     snap 1-empty
python3 dev/fake.py start; python3 bin/emba open > /dev/null; snap 2-overview
python3 dev/fake.py ask > /dev/null &
                                                       snap 3-approval 1.6
python3 bin/emba deny > /dev/null; wait $!
python3 dev/fake.py done;                              snap 4-finished 1.6
python3 dev/fake.py limit 86;                          snap 5-limit 1.6
python3 bin/emba close > /dev/null;                    snap 6-pill 1.2
python3 bin/emba care > /dev/null;                     snap 7-care
python3 bin/emba ask > /dev/null;                      snap 8-ask
python3 dev/fake.py end; python3 bin/emba close > /dev/null
python3 dev/sheet.py dev/views.png $o/*.png
