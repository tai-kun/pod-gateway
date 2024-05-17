#!/usr/bin/env bash
#
# This script starts the sidecar for the gateway container.

set -euo pipefail

# shellcheck source=/dev/null
. /pgw/prelude.sh

# ------------------------------------------------------------------------------
# Set the constants
# ------------------------------------------------------------------------------

VXLAN_ID='3150'
GATEWAY_VXLAN_FIRST_DYNAMIC_IP='20'

vxlan="vxlan$VXLAN_ID"

# ------------------------------------------------------------------------------
# Start the sidecar
# ------------------------------------------------------------------------------

echo 'Starting sidecar' | log_debug

# Make a copy of the original resolv.conf
# (so we can get the K8S DNS in case of a container reboot)
if [ ! -f /etc/resolv.conf.org ]; then
    /pgw/gateway/copy_resolv.sh
fi

# Get Kubernetes DNS
k8s_dns="$(grep nameserver /etc/resolv.conf.org | cut -d' ' -f2)"
assert_ipv4 "$k8s_dns"

echo "K8s DNS: $k8s_dns" | log_debug

# Set up the DHCP server
dhcp_range_0="$PGW_VXLAN_IP_NETWORK.$GATEWAY_VXLAN_FIRST_DYNAMIC_IP"
dhcp_range_1="$PGW_VXLAN_IP_NETWORK.255"
dhcp_lease_time='12h'
cat <<EOF >/etc/dnsmasq.d/pod-gateway.conf
# DHCP server settings
interface=$vxlan
bind-interfaces

# Dynamic IPs assigned to PODs - we keep a range for static IPs
dhcp-range=$dhcp_range_0,$dhcp_range_1,$dhcp_lease_time

# For debugging purposes, log each DNS query as it passes through dnsmasq.
log-queries

# Log lots of extra information about DHCP transactions.
log-dhcp

# Log to stdout
log-facility=-

# Clear DNS cache on reload
clear-on-reload

# /etc/resolv.conf cannot be monitored by dnsmasq since it is in a different
# file system and dnsmasq monitors directories only copy_resolv.sh is used to
# copy the file on changes.
resolv-file=/etc/resolv.conf.org
EOF

for local_cidr in $PGW_LOCAL_CIDRS; do
    cat <<EOF >>/etc/dnsmasq.d/pod-gateway.conf
# Send $local_cidr DNS queries to the K8S DNS server
server=/$local_cidr/$k8s_dns
EOF
done

dnsmasq -k &
dnsmasq=$!

echo "dnsmasq started with PID: $dnsmasq" | log_debug

# inotifyd to keep sync with the resolv.conf copy
inotifyd /pgw/gateway/copy_resolv.sh /etc/resolv.conf:ce &
inotifyd=$!

echo "inotifyd started with PID: $inotifyd" | log_debug

# Starting an HTTP/1.1 server and returning the pod's IP address.
# This IP address is necessary for the client to configure VXLAN.
socat TCP-LISTEN:3150,fork,reuseaddr SYSTEM:/pgw/gateway/resp-ip.sh &
socat=$!

echo "socat started with PID: $socat" | log_debug

function _kill_procs() {
    echo 'Terminating sidecar' | log_debug

    # Terminate Dnsmasq
    kill -TERM $dnsmasq || true
    wait $dnsmasq
    rc=$?

    # Terminate inotifyd
    kill -TERM $inotifyd || true
    wait $inotifyd
    rc=$(($rc || $?))

    # Terminate socat
    kill -TERM $socat || true
    wait $socat
    rc=$(($rc || $?))

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
