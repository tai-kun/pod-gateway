#!/usr/bin/env bash
#
# This script starts the sidecar for the client container.

set -euo pipefail

# shellcheck source=/dev/null
. /pgw/prelude.sh

# ------------------------------------------------------------------------------
# Start the client
# ------------------------------------------------------------------------------

echo 'Starting sidecar' | log_debug

# Logs the gateway pod's service name
if [[ -f /pgw/gateway-pod-service ]]; then
    echo "Gateway pod's service: $(cat /pgw/gateway-pod-service)" | log_debug
else
    echo "Gateway pod's service: $1" | log_debug
fi

{
    # Continuously ping the gateway pod
    while true; do
        sleep "$PGW_CLIENT_PING_INTERVAL"

        # If the gateway pod is reachable, continue
        if ping -c 1 "$PGW_GATEWAY_VXLAN_IP"; then
            continue
        fi

        # If the gateway pod is not reachable, block all outbound traffic
        # and reconnect to the gateway pod
        ip route del default || true

        echo 'Blocked all outbound traffic.' | log_warn

        if [[ -f /pgw/gateway-pod-service ]]; then
            gateway_pod_service="$(cat /pgw/gateway-pod-service)"
        else
            gateway_pod_service="$1"
        fi

        echo "Reconnecting to http://$gateway_pod_service" | log_debug

        /pgw/client/init.sh || true
    done
} &
sidecar=$!

echo "Sidecar started with PID: $sidecar" | log_debug

function _kill_procs() {
    echo 'Terminating sidecar' | log_debug

    # Terminate the sidecar
    kill -TERM $sidecar || true
    wait $sidecar
    rc=$?

    echo "Terminated with RC: $rc" | log_debug

    exit $rc
}

# Trap the termination signals
trap _kill_procs SIGTERM

echo 'Sidecar started' | log_debug

# Wait for the processes to finish
wait -n

echo 'Terminating sidecar' | log_debug

# Kill the processes
_kill_procs
