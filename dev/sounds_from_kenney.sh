#!/bin/sh
# Rebuild assets/sounds: Emba's 8-bit sounds, cut from Kenney's "Digital Audio"
# pack (CC0, public domain, kenney.nl). Each line: Emba's name, the source
# file, how many seconds of it to keep. Every sound is trimmed short, faded
# out and brought to the same, modest loudness.
#   sh dev/sounds_from_kenney.sh
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d)
curl -fsSL -o "$T/k.zip" "https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip"
unzip -q "$T/k.zip" -d "$T"
rm -f assets/sounds/*.wav
mkdir -p assets/sounds
while read -r name file keep; do
    fade=$(echo "$keep" | awk '{printf "%.3f", $1 * 0.35}')
    start=$(echo "$keep $fade" | awk '{printf "%.3f", $1 - $2}')
    ffmpeg -loglevel error -y -i "$T/Audio/$file.ogg" -t "$keep" -ac 1 -ar 44100 \
        -af "afade=t=out:st=$start:d=$fade,loudnorm=I=-24:TP=-6:LRA=7" "assets/sounds/$name.wav"
done << EOF
open phaserUp5 0.25
close phaserDown2 0.25
hi pepSound3 0.4
ask threeTone1 0.6
done powerUp2 0.46
gulp lowDown 0.35
boop pepSound1 0.25
annoyed lowRandom 0.35
dizzy phaseJump1 0.46
love highUp 0.4
hop phaseJump2 0.3
spin phaserUp6 0.33
sneeze phaseJump5 0.3
yawn highDown 0.5
wake phaserUp4 0.36
eat pepSound4 0.4
play phaseJump3 0.35
listen tone1 0.3
low lowThreeTone 0.6
EOF
chmod -R u+w "$T"; rm -rf "$T"
ls assets/sounds | tr '\n' ' '; echo
