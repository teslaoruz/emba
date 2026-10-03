#!/bin/sh
# Use Emba like a person would, with the real mouse and keyboard, and keep a
# screenshot of every step in dev/walk/. Runs a separate Emba on its own socket.
#   sh dev/walkthrough.sh DECOY_ADDRESS
# Keystrokes only go out while DECOY (a terminal running `cat`) has focus.
cd "$(dirname "$0")/.."
read -r W H X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.x) \(.y)"')
EOF
R=$((X + W))                                   # right edge of the screen
geo="$((R - 500)),$Y 500x260"
out=dev/walk
rm -rf $out && mkdir -p $out
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1 || hyprctl dispatch movecursor "$1" "$2" > /dev/null; ydotool mousemove -x 1 -y 0 > /dev/null; ydotool mousemove -x -1 -y 0 > /dev/null; }
click() { ydotool click 0xC0 > /dev/null; }
shot() { sleep "${2:-0.9}"; grim -g "$geo" "$out/$1.png"; }
fake() { python3 dev/fake.py "$@"; }
decoy=${1:-}  # without a decoy terminal the typing steps are skipped
guard() { [ "$(hyprctl activewindow -j | jq -r .address)" = "$decoy" ] || { echo "ABORT: focus moved off the decoy"; exit 1; }; }

python3 bin/emba quit > /dev/null; sleep 0.6
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-walk.sock"
emba() { python3 bin/emba "$@" > /dev/null; }
to $((R - 700)) $((Y + 500))
emba start; sleep 1.5
[ -n "$decoy" ] && { python3 bin/emba focus "$decoy" > /dev/null; sleep 0.4; guard; }
shot 01-hidden

to $((R - 3)) $((Y + 3));               shot 02-peek 0.35
                                        shot 03-welcome 1.4
to $((R - 300)) $((Y + 110))            # over the ask field (below the tabs)
click;                                  shot 04-ask-open 0.8
[ -n "$decoy" ] && guard && wtype "hello there";                    shot 05-ask-typing 0.4
[ -n "$decoy" ] && guard && wtype -k Escape;                        shot 06-after-esc 0.8

to $((R - 700)) $((Y + 500)); sleep 1.5
fake start;                             shot 07-compact 1.5
to $((R - 60)) $((Y + 20));             shot 08-overview 1.4
to $((R - 300)) $((Y + 75));            shot 09-row-hover 0.6

fake ask > /dev/null &
                                        shot 10-approval 1.6
to $((R - 240)) $((Y + 113));           shot 11-hover-always 0.6
to $((R - 157)) $((Y + 113)); click;    shot 12-after-allow 0.9
wait

fake done;                              shot 13-finished 1.4

to $((R - 410)) $((Y + 60)); click;     shot 14-care 1.0     # click Emba
ydotool click 0xC0 > /dev/null; sleep 0.12; click; shot 15-feed 0.5
to $((R - 150)) $((Y + 90)); click;     shot 16-ball 0.6
to $((R - 420)) $((Y + 60))                                 # rub over Emba to pet
for i in 1 2 3 4 5 6; do to $((R - 395)) $((Y + 62)); sleep 0.07; to $((R - 425)) $((Y + 62)); sleep 0.07; done
                                        shot 17-petted 0.4

to $((R - 30)) $((Y + 30)); click;      shot 18-back 1.0     # back to the sessions
to $((R - 30)) $((Y + 30)); click;      shot 18-settings-click 1.2   # the gear
hyprctl clients -j | jq -r '.[] | select(.title=="Emba") | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -1 > $out/settings.geo
[ -s $out/settings.geo ] && grim -g "$(cat $out/settings.geo)" "$out/19-settings.png"

to $((R - 800)) $((Y + 600));           shot 20-left 2.5
fake end
emba quit
unset EMBA_SOCKET
sh dev/run.sh > /dev/null
ls $out
