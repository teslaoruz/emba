#!/bin/sh
# (Re)start emba from this checkout; log in dev/run.log.
#   dev/run.sh          restart
#   dev/run.sh stop     stop
#   dev/run.sh shot     screenshot the island's corner to dev/island.png
cd "$(dirname "$0")/.."
pidf=dev/qs.pid
case "${1:-}" in
stop)
    [ -f $pidf ] && kill "$(cat $pidf)" 2>/dev/null
    rm -f $pidf
    ;;
shot)
    mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x) \(.y) \(.width)"')
    set -- $mon
    grim -g "$(($1 + $3 - 500)),$2 500x400" dev/island.png
    echo dev/island.png
    ;;
*)
    [ -f $pidf ] && kill "$(cat $pidf)" 2>/dev/null
    qs -p . > dev/run.log 2>&1 &
    echo $! > $pidf
    sleep 2.5
    grep -iE "error|warn|caused" dev/run.log | head -20
    ;;
esac
