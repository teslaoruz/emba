#!/bin/sh
# Talk to Emba through a virtual microphone: Piper's speech goes into a
# temporary PipeWire source that Emba records from like any mic. Your default
# input is put back at the end.
#   sh dev/voice_test.sh "Emba, play ball!" [seconds to wait]
cd "$(dirname "$0")/.."
said=$1 wait=${2:-8}
.venv/bin/python dev/tts_wav.py dev/said.wav "$said"

old=$(pactl get-default-source)
sink=$(pactl load-module module-null-sink sink_name=emba_test sink_properties=device.description=EmbaTest)
mic=$(pactl load-module module-remap-source master=emba_test.monitor source_name=emba_mic)
pactl set-default-source emba_mic
cleanup() { pactl set-default-source "$old"; pactl unload-module "$mic"; pactl unload-module "$sink"; }
trap cleanup EXIT

python3 bin/emba listen
sleep 1.5
pw-play --target emba_test dev/said.wav
sleep "$wait"
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
grim -g "$((X + W - 500)),$Y 500x230" dev/voiced.png
echo "default input back to: $old"
