#!/usr/bin/env bash
#
# This script initializes the client container.

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
# Init the client
# ------------------------------------------------------------------------------

echo 'Initing client' | log_debug

# Get the gateway pod's service name from the argument
gateway_pod_service="$1"
echo "Gateway pod's service: $gateway_pod_service" | log_debug

# Get the gateway pod's IP address
gateway_pod_ip="$(curl -fs "http://$gateway_pod_service")"
echo "Gateway pod's IP: $gateway_pod_ip" | log_debug
assert_ipv4 "$gateway_pod_ip"

# Records the Pod's service name to inform the sidecar container.
# This is only valid if the /pgw directory is shared between containers.
echo -n "$gateway_pod_service" >/pgw/gateway-pod-service

# Debugging information about the client
ip addr | log_debug
ip route | log_debug

# In re-trying the client, the VXLAN interface might already exist
# If it does, delete it
if ip addr | grep -q "$vxlan"; then
    ip link del "$vxlan"
    k8s_gateway_ip=''
else
    k8s_gateway_ip="$(ip route | awk '/default/ { print $3 }')"
fi

# Delete the default route
ip route del 0/0 || true

# If the K8s gateway IP is an IPv4 address,
# add a route to the gateway pod through the K8s gateway
# and add routes to the local IPs through the K8s gateway
if is_ipv4 "$k8s_gateway_ip"; then
    echo "K8s gateway IP: $k8s_gateway_ip" | log_debug

    # Add a route to the gateway pod through the K8s gateway
    ip route add "$gateway_pod_ip" via "$k8s_gateway_ip" || true

    # Add routes to the local IP through the K8s gateway
    for local_cidr in $PGW_LOCAL_CIDRS; do
        ip route add "$local_cidr" via "$k8s_gateway_ip" || true
    done
fi

# We should not be able to ping the internet yet
if ping -c 1 8.8.8.8; then
    echo 'Should not be able to ping' | log_err
    exit 255
fi

# Debugging information about the client
ip addr | log_debug
ip route | log_debug

# Create tunnel NIC
ip link add "$vxlan" \
    type vxlan \
    id "$VXLAN_ID" \
    remote "$gateway_pod_ip" \
    dstport 4789 \
    dev "$DEVICE_INTERFACE" || true
ip link set up dev "$vxlan"

# Configure the DHCP client
cat <<EOF >/etc/dhclient.conf
backoff-cutoff 2;
initial-interval 1;
reboot 0;
retry 10;
select-timeout 0;
timeout 30;

interface "$vxlan"
 {
  request subnet-mask,
          broadcast-address,
          routers;
          #domain-name-servers;
  require routers,
          subnet-mask;
          #domain-name-servers;
 }
EOF

# Start the DHCP client
dhclient -v -cf /etc/dhclient.conf "$vxlan"

echo "VXLAN IP: $(ip addr show "$vxlan" | awk '/inet / { print $2 }')" | log_debug

# Debugging information about the client
ip addr | log_info
ip route | log_info

# Check if the gateway pod is reachable
ping -c 1 "$PGW_GATEWAY_VXLAN_IP"
# Check if the internet is reachable
ping -c 1 8.8.8.8

echo 'Client inited' | log_debug
