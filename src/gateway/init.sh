#!/usr/bin/env bash
#
# This script initializes the gateway container.

set -euo pipefail

# shellcheck source=/dev/null
. /pgw/prelude.sh

# ------------------------------------------------------------------------------
# Set the constants
# ------------------------------------------------------------------------------

VXLAN_ID='3150'
DEVICE_INTERFACE='eth0'

vxlan="vxlan$VXLAN_ID"

# ------------------------------------------------------------------------------
# Init the gateway
# ------------------------------------------------------------------------------

echo -n 'Initing gateway' | log_debug

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Add VXLAN interface if it does not exist
# It might already exists in case initContainer is restarted
if ip addr | grep -q "$vxlan"; then
    ip link del "$vxlan"
fi

# Create VXLAN NIC
ip link add "$vxlan" \
    type vxlan \
    id "$VXLAN_ID" \
    dstport 4789 \
    dev "$DEVICE_INTERFACE" || true
ip addr add "$PGW_GATEWAY_VXLAN_IP/24" dev "$vxlan" || true
ip link set up dev "$vxlan"

# Enable outbound NAT
iptables -t nat -A POSTROUTING -j MASQUERADE

echo -n 'Gateway inited' | log_debug
