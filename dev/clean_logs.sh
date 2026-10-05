#!/bin/sh
# Remove Quickshell's runtime folders of Emba instances that have exited.
# Debug runs (QSG_RENDER_TIMING, console.log per frame) leave logs of
# gigabytes in /run/user/<uid>, which is RAM and small.
#   sh dev/clean_logs.sh
base="$XDG_RUNTIME_DIR/quickshell/by-id"
for d in "$base"/*/; do
    [ -f "$d/log.log" ] || continue
    head -c 400 "$d/log.log" | grep -q 'emba/shell.qml' || continue   # Emba's only
    pid=$(ls -l "$XDG_RUNTIME_DIR/quickshell/by-pid" | awk -v d="$(basename "$d")" '$NF ~ d"$" {print $9}')
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then continue; fi        # still running
    echo "removing $(du -sh "$d" | cut -f1) $(basename "$d")"
    rm -rf "$d"
done
find "$XDG_RUNTIME_DIR/quickshell/by-pid" -xtype l -delete
df -h "$XDG_RUNTIME_DIR" | tail -1
