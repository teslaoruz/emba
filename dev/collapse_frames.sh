#!/bin/sh
# The island closing, then opening, a frame every 33 ms, grabbed from inside.
#   sh dev/collapse_frames.sh -> dev/close.png, dev/open.png
cd "$(dirname "$0")/.."
o=$PWD/dev/cf; rm -rf $o; mkdir -p $o
python3 dev/fake.py start
python3 bin/emba open > /dev/null; sleep 1.5
python3 bin/emba snapshot "$o/c%d.png"; python3 bin/emba close > /dev/null; sleep 1.5
python3 bin/emba snapshot "$o/o%d.png"; python3 bin/emba open > /dev/null; sleep 1.5
python3 bin/emba close > /dev/null; python3 dev/fake.py end
python3 dev/readme_views.py dev/close.png $(ls $o/c*.png | awk 'NR%2==1' | head -10)
python3 dev/readme_views.py dev/open.png $(ls $o/o*.png | awk 'NR%2==1' | head -10)
