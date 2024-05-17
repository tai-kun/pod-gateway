#!/usr/bin/env bash
#
# This script responds with the IP address of the gateway container.

# This IP address is necessary for the client to configure VXLAN.
content="$(ip address show eth0 | awk '/inet / { print $2 }' | cut -d'/' -f1)"

echo 'HTTP/1.1 200 OK'
echo 'Content-Type: text/plain'
echo "Content-Length: $(echo -n "$content" | wc -c)"
echo
echo -n "$content"
