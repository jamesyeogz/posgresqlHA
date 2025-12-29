#!/bin/bash
# =============================================================================
# Health Check Script
# Returns exit code 0 if healthy, non-zero otherwise
# =============================================================================

PATRONI_HOST=${PATRONI_HOST:-localhost}
PATRONI_PORT=${PATRONI_PORT:-8008}

# Check Patroni health endpoint
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' "http://${PATRONI_HOST}:${PATRONI_PORT}/health" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
    exit 0
else
    exit 1
fi
