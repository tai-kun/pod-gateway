#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
. /pgw/prelude.sh

arg1="${1:-}"
arg2="${2:-}"

case "$arg1" in
client)
    case "$arg2" in
    init)
        /pgw/client/init.sh "${@:3}"
        ;;

    start)
        /pgw/client/sidecar.sh "${@:3}"
        ;;

    *)
        echo -n "Invalid argument: $arg2" | log_err
        exit 1
        ;;
    esac
    ;;

gateway)
    case "$arg2" in
    init)
        /pgw/gateway/init.sh "${@:3}"
        ;;

    start)
        /pgw/gateway/sidecar.sh "${@:3}"
        ;;

    *)
        echo -n "Invalid argument: $arg2" | log_err
        exit 1
        ;;
    esac
    ;;

*)
    echo -n "Invalid argument: $arg1" | log_err
    exit 1
    ;;
esac
