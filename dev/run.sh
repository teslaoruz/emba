#!/bin/sh
# (Re)start Emba from this checkout; log in dev/run.log.
#   dev/run.sh          restart (stops whichever Emba is running, however it was started)
#   dev/run.sh stop     stop
#   dev/run.sh shot     screenshot the island's corner to dev/island.png
cd "$(dirname "$0")/.."
pidf=dev/qs.pid
stop() {
    python3 bin/emba quit > /dev/null 2>&1
    [ -f $pidf ] && kill "$(cat $pidf)" 2> /dev/null
    rm -f $pidf
    sleep 1
}
case "${1:-}" in
stop)
    stop
    ;;
shot)
    mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x) \(.y) \(.width)"')
    set -- $mon
    grim -g "$(($1 + $3 - 500)),$2 500x400" dev/island.png
    echo dev/island.png
    ;;
*)
    stop
    qs -p . > dev/run.log 2>&1 &
    echo $! > $pidf
    sleep 2.5
    grep -iE "error|warn|caused" dev/run.log | grep -viE "socket" | head -20
    ;;
esac
