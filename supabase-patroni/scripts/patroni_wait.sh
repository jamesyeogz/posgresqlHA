#!/bin/bash
# =============================================================================
# Patroni Wait Script
# Waits for Patroni to be ready and optionally executes a command
# Based on Zalando Spilo's patroni_wait.sh
# =============================================================================

ROLE=primary
INTERVAL=10
TIMEOUT=""
HOST=localhost
PORT=8008

usage() {
    cat <<__EOT__
Usage: $(basename "$0") [OPTIONS] [-- COMMAND [ARG1] [ARG2]]

Options:
    -h, --host      Patroni REST API host (default: $HOST)
    -p, --port      Patroni REST API port (default: $PORT)
    -i, --interval  Polling interval in seconds (default: $INTERVAL)
    -r, --role      Role to wait for: primary or replica (default: $ROLE)
    -t, --timeout   Fail after TIMEOUT seconds (default: no timeout)
    --help          Show this help message

Waits for the specified ROLE to become available.
Optionally executes COMMAND after the role is available.
Returns exit code 2 if timeout is reached.

Examples:
    $(basename "$0") -r primary
    $(basename "$0") -r replica -t 300 -- echo "Replica is ready"
    $(basename "$0") -t 600 -- pg_basebackup -h localhost -D /backup
__EOT__
    exit 0
}

while [ $# -gt 0 ]; do
    case $1 in
        -h|--host)
            HOST=$2
            shift
            ;;
        -p|--port)
            PORT=$2
            shift
            ;;
        -r|--role)
            ROLE=$2
            shift
            ;;
        -i|--interval)
            INTERVAL=$2
            shift
            ;;
        -t|--timeout)
            TIMEOUT=$2
            shift
            ;;
        --help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

# Validate role
case $ROLE in
    primary|leader|master)
        ENDPOINT="primary"
        ;;
    replica|standby|secondary)
        ENDPOINT="replica"
        ;;
    *)
        echo "Invalid role: $ROLE (must be primary or replica)"
        exit 1
        ;;
esac

echo "Waiting for Patroni to report as $ROLE..."

# Calculate cutoff time if timeout specified
[ -n "$TIMEOUT" ] && CUTOFF=$(($(date +%s) + TIMEOUT))

while true; do
    # Check if Patroni reports the expected role
    HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' "http://${HOST}:${PORT}/${ENDPOINT}" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Patroni is now $ROLE (HTTP $HTTP_CODE)"
        break
    fi
    
    # Check timeout
    if [ -n "$TIMEOUT" ] && [ "$CUTOFF" -le "$(date +%s)" ]; then
        echo "Timeout waiting for $ROLE role"
        exit 2
    fi
    
    echo "Waiting for $ROLE role... (HTTP code: $HTTP_CODE)"
    sleep "$INTERVAL"
done

# Execute command if provided
if [ $# -gt 0 ]; then
    echo "Executing: $*"
    exec "$@"
fi
