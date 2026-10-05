#!/bin/sh
# Use Emba like a person, with the real mouse, on a separate Emba with its own
# settings, recording frames from inside the island for each scenario.
#   sh dev/usertest.sh [SCENARIO...]     -> dev/ut/<scenario>.png contact sheets
# Scenarios: corner pill tabs approval question finished care models usage edges
# Clicks only land on Emba's own island; nothing is typed.
cd "$(dirname "$0")/.."
read -r W H X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.x) \(.y)"')
EOF
R=$((X + W)) B=$((Y + H))
out=$PWD/dev/ut
mkdir -p "$out"
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-ut.sock"
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{"plugins": []}' > "$T/emba/config.json"; export XDG_CONFIG_HOME=$T

to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1; ydotool mousemove -x 1 -y 0 > /dev/null; ydotool mousemove -x -1 -y 0 > /dev/null; }
glide() { # move like a hand: $1,$2 -> $3,$4 in 10 steps
    i=1; while [ $i -le 10 ]; do to $(($1 + ($3 - $1) * i / 10)) $(($2 + ($4 - $2) * i / 10)); sleep 0.025; i=$((i + 1)); done; }
click() { ydotool click 0xC0 > /dev/null; }
emba() { python3 bin/emba "$@" > /dev/null 2>&1; }
fake() { python3 dev/fake.py "$@" > /dev/null 2>&1; }
away() { to $((R - 900)) $((Y + 600)); }
rec() { rm -rf "$out/f"; mkdir -p "$out/f"; emba snapshot "$out/f/%d.png"; }     # 30 frames, ~1.2 s
sheet() { name=$1; shift; python3 dev/sheet.py "$out/$name.png" "$@"; }
pick() { ls "$out"/f/*.png 2>/dev/null | awk -v n="$1" 'NR % n == 1'; }          # every n-th frame
keep() { mkdir -p "$out/$1"; cp "$out"/f/*.png "$out/$1/" 2>/dev/null; }        # frames for a closer look

start() {
    emba quit; sleep 0.5
    qs -p . > "$out/qs.log" 2>&1 &
    QS=$!
    sleep 3.2   # past the hello
    away; sleep 1
}
stop() { fake end; emba quit; kill $QS 2> /dev/null; sleep 0.5; }

corner() {   # hover the corner from nothing, then leave
    away; sleep 1.5
    rec; glide $((R - 200)) $((Y + 200)) $((R - 3)) $((Y + 3)); sleep 1.4; keep corner-in
    sheet corner-in $(pick 3)
    rec; glide $((R - 3)) $((Y + 3)) $((R - 600)) $((Y + 500)); sleep 1.8; keep corner-out
    sheet corner-out $(pick 3)
}
pill() {     # sessions running: hover the pill, leave
    fake start; sleep 1.5
    rec; glide $((R - 600)) $((Y + 300)) $((R - 80)) $((Y + 20)); sleep 1.4; keep pill-in
    sheet pill-in $(pick 3)
    rec; away; sleep 1.8; keep pill-out
    sheet pill-out $(pick 3)
}
tabs() {     # open, switch to Chat and back
    emba open; sleep 1.3; to $((R - 300)) $((Y + 30))
    rec; to $((R - 236)) $((Y + 31)); sleep 0.2; click; sleep 1.2; keep tabs-chat
    sheet tabs-chat $(pick 3)
    rec; to $((R - 316)) $((Y + 31)); sleep 0.2; click; sleep 1.2; keep tabs-back
    sheet tabs-back $(pick 3)
    away; sleep 3.5
}
approval() { # a request while closed, then Deny; another, then Always
    fake start; emba close; away; sleep 1.5
    rec; (fake ask &); sleep 1.4; keep approval-in
    sheet approval-in $(pick 3)
    to $((R - 327)) $((Y + 113)); sleep 0.4
    rec; click; sleep 1.2; keep approval-deny
    sheet approval-deny $(pick 3)
    away; sleep 2
}
question() { # a question from Claude: pick an option, Send
    away; sleep 1
    sh dev/question_test.sh > /dev/null 2>&1 & QT=$!
    sleep 1.3
    rec; to $((R - 230)) $((Y + 118)); sleep 0.3; click; sleep 1.2; keep question-pick
    sheet question-pick $(pick 3)
    wait $QT
}
finished() { # work is done: the pop-up, then it goes away by itself
    fake start; emba close; away; sleep 1.5
    rec; fake done; sleep 1.4; keep finished-in
    sheet finished-in $(pick 3)
    sleep 4; rec; sleep 1.4; keep finished-later
    sheet finished-later $(pick 3)
}
care() {     # click Emba, double-click, rub
    emba care; sleep 1.3
    to $((R - 410)) $((Y + 55)); sleep 0.3
    rec; click; sleep 1.2; keep care-poke
    sheet care-poke $(pick 3)
    rec; click; sleep 0.1; click; sleep 1.2; keep care-feed
    sheet care-feed $(pick 3)
    rec; i=0; while [ $i -lt 6 ]; do to $((R - 395)) $((Y + 55)); sleep 0.07; to $((R - 425)) $((Y + 55)); sleep 0.07; i=$((i + 1)); done; sleep 0.6; keep care-pet
    sheet care-pet $(pick 3)
    away; sleep 2
}
models() {   # the model chip in the chat
    emba ask; sleep 1.3
    to $((R - 112)) $((Y + 71)); sleep 0.3
    rec; click; sleep 1.2; keep models-open
    sheet models-open $(pick 3)
    away; sleep 3.5
}
usage() {    # the usage line on the sessions tab
    fake limit 40; fake start; emba open; sleep 1.3
    rec; to $((R - 230)) $((Y + 87)); sleep 0.3; click; sleep 1.2; keep usage-open
    sheet usage-open $(pick 3)
    away; sleep 2
}
edges() {    # left edge, bottom: the pill and the open card
    for pos in right left bottom; do
        emba set position $pos; sleep 1.5; fake start; sleep 1.5
        rec; sleep 1.2; keep "edge-$pos"
        emba open; sleep 1.5; rec; sleep 1.2; keep "edge-$pos-open"
        sheet "edge-$pos" "$out/edge-$pos/00.png" "$out/edge-$pos-open/29.png"
        emba close; fake end; sleep 1
    done
    emba set position top-right
}

start
for s in ${@:-corner pill tabs approval question finished care models usage edges}; do
    echo "== $s"; $s
done
stop
ls "$out"/*.png
