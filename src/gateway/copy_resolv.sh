#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
. /pgw/prelude.sh

cp /etc/resolv.conf /etc/resolv.conf.org
echo 'Copied /etc/resolv.conf to /etc/resolv.conf.org' | log_debug
