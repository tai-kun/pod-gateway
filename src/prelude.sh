#!/usr/bin/env bash
#
# This script sets up the prelude for the gateway and client scripts.

set -euo pipefail

# ------------------------------------------------------------------------------
# Get and set the default values for the environment variables
# ------------------------------------------------------------------------------

export PGW_LOG_LEVEL="${PGW_LOG_LEVEL:-warn}"
export PGW_LOG_TRANSPORTS="${PGW_LOG_TRANSPORTS:-console}"
export PGW_LOG_FILE_PATH="${PGW_LOG_FILE_PATH:-/var/log/pgw.log}"
export PGW_VXLAN_IP_NETWORK="${PGW_VXLAN_IP_NETWORK:-172.29.0}"
export PGW_LOCAL_CIDRS="${PGW_LOCAL_CIDRS:-192.168.0.0/16 10.0.0.0/8}"
export PGW_CLIENT_PING_INTERVAL="${PGW_CLIENT_PING_INTERVAL:-10}"

# ------------------------------------------------------------------------------
# Set the derived values for the environment variables
# ------------------------------------------------------------------------------

export PGW_GATEWAY_VXLAN_IP="$PGW_VXLAN_IP_NETWORK.1"

# ------------------------------------------------------------------------------
# Setup the logger
# ------------------------------------------------------------------------------

function cleanup_logger() {
    # If the logger is running, send a close signal and wait for it to exit
    if [ -v logger_pid ]; then
        echo '__CLOSE__' >&3
        wait $logger_pid
    fi

    # Close the file descriptor
    exec 3>&-

    # Remove the temporary directory in which the logger FIFO is created
    if [ -v logger_tmp ]; then
        rm -rf "$logger_tmp"
    fi
}

# Cleanup the logger when the script exits
trap cleanup_logger EXIT

# Create a FIFO for the logger
logger_tmp="$(mktemp -d)"
logger_fifo="$logger_tmp/logger_fifo"
mkfifo "$logger_fifo"

# Start the logger in the background
# This means that the file descriptor 3 is enabled for writing
/pgw/pgw-logger "$logger_fifo" &
logger_pid=$!

# Open the file descriptor 3 for writing
exec 3>"$logger_fifo"

# Convert the log level to a number
# The log levels are as follows:
#   - debug: 10
#   - info: 20
#   - err: 30
#
# Arguments:
#   $1: The log level
# Returns:
#   The log level as a number
function log_level_to_number() {
    case "${1,,}" in
    debug | trace) echo -n 10 ;;
    info) echo -n 20 ;;
    err | error | warn | warning) echo -n 30 ;;
    *) echo -n 20 ;;
    esac
}

# Set the log level as a number
log_level_number="$(log_level_to_number "$PGW_LOG_LEVEL")"

# Record debug level log messages
#
# Arguments:
#   Pipe the message to this function
# Returns:
#   None
function log_debug() {
    if [ 10 -ge "$log_level_number" ]; then
        echo '__BEGIN__' >&3
        echo 'DEBUG' >&3
        cat >&3
        echo '__END__' >&3
    fi
}

# Record informatory log messages
#
# Arguments:
#   Pipe the message to this function
# Returns:
#   None
function log_info() {
    if [ 20 -ge "$log_level_number" ]; then
        echo '__BEGIN__' >&3
        echo 'INFO' >&3
        cat >&3
        echo '__END__' >&3
    fi
}

# Record error log messages
#
# Arguments:
#   Pipe the message to this function
# Returns:
#   None
function log_err() {
    if [ 30 -ge "$log_level_number" ]; then
        echo '__BEGIN__' >&3
        echo 'ERR' >&3
        cat >&3
        echo '__END__' >&3
    fi
}

# Record configurations

echo -n "[config] transports: $PGW_LOG_TRANSPORTS" | log_debug
echo -n "[config] vxlan ip network: $PGW_VXLAN_IP_NETWORK" | log_debug
echo -n "[config] local CIDRs: $PGW_LOCAL_CIDRS" | log_debug
echo -n "[config] client ping interval: $PGW_CLIENT_PING_INTERVAL s" | log_debug

# ------------------------------------------------------------------------------
# Define the utility functions for validating values
# ------------------------------------------------------------------------------

# Regular expressions for validating IPv4 addresses
IPV4_REGEX='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'

# Check if the given string is a valid IPv4 address
#
# Arguments:
#   $1: The string to validate
# Returns:
#   0 if the string is a valid IPv4 address, 1 otherwise
function is_ipv4() {
    [[ "$1" =~ $IPV4_REGEX ]]
}

# Check if the given string is a valid CIDR
#
# Arguments:
#   $1: The string to validate
# Returns:
#   0 if the string is a valid CIDR, 1 otherwise
function is_cidr() {
    local IP
    local MASK

    IFS='/' read -r IP MASK <<<"$1"

    if ! is_ipv4 "$IP"; then
        return 1
    fi

    if ! [[ "$MASK" == 0 || "$MASK" =~ ^[1-9][0-9]*$ ]]; then
        return 1
    fi

    [[ "$MASK" -ge 0 && "$MASK" -le 32 ]]
}

# Check if the given string is a valid unsigned 32-bit integer
#
# Arguments:
#   $1: The string to validate
# Returns:
#   0 if the string is a valid unsigned 32-bit integer, 1 otherwise
function is_uint32() {
    if ! [[ "$1" == 0 || "$1" =~ ^[1-9][0-9]*$ ]]; then
        return 1
    fi

    [[ "$1" -ge 0 && "$1" -le 4294967295 ]]
}

# Asserts if the given string is a valid IPv4 address
#
# Arguments:
#   $1: The string to validate
# Exits with error message and status 1 if the string is not a valid IPv4 address
function assert_ipv4() {
    if ! is_ipv4 "$1"; then
        echo -n "Invalid IPv4 address: $1" | log_err
        exit 1
    fi
}

# Asserts if the given string is a valid CIDR
#
# Arguments:
#   $1: The string to validate
# Exits with error message and status 1 if the string is not a valid CIDR
function assert_cidrs() {
    local cidr

    for cidr in $1; do
        if ! is_cidr "$cidr"; then
            echo -n "Invalid CIDR: $cidr" | log_err
            exit 1
        fi
    done
}

# Asserts if the given string is a valid unsigned 32-bit integer
#
# Arguments:
#   $1: The string to validate
# Exits with error message and status 1 if the string is not a valid unsigned 32-bit integer
function assert_uint32() {
    if ! is_uint32 "$1"; then
        echo -n "Invalid uint32 value: $1" | log_err
        exit 1
    fi
}

# Validate the environment variables

assert_ipv4 "$PGW_GATEWAY_VXLAN_IP"
assert_cidrs "$PGW_LOCAL_CIDRS"
assert_uint32 "$PGW_CLIENT_PING_INTERVAL"
