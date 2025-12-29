#!/bin/bash
# =============================================================================
# Cluster Status Script
# Shows the current status of the Patroni cluster
# =============================================================================

set -e

PATRONI_HOST=${PATRONI_HOST:-localhost}
PATRONI_PORT=${PATRONI_PORT:-8008}

echo "========================================"
echo "Supabase Patroni Cluster Status"
echo "========================================"
echo ""

# Check if patronictl is available
if command -v patronictl &> /dev/null; then
    echo "Cluster Members:"
    echo "----------------"
    patronictl list 2>/dev/null || echo "Failed to get cluster list"
    echo ""
fi

# Get node info from REST API
echo "Local Node Info:"
echo "----------------"
NODE_INFO=$(curl -sf "http://${PATRONI_HOST}:${PATRONI_PORT}/" 2>/dev/null)
if [ -n "$NODE_INFO" ]; then
    echo "$NODE_INFO" | jq -r '
        "  Name: \(.patroni.name // "N/A")",
        "  Role: \(.role // "N/A")",
        "  State: \(.state // "N/A")",
        "  Timeline: \(.timeline // "N/A")",
        "  Cluster: \(.cluster_unlocked // "N/A" | if . then "unlocked" else "locked" end)",
        "  Server Version: \(.server_version // "N/A")"
    ' 2>/dev/null || echo "$NODE_INFO"
else
    echo "  Could not connect to Patroni API at http://${PATRONI_HOST}:${PATRONI_PORT}/"
fi
echo ""

# Check replication status
echo "Replication Status:"
echo "-------------------"
PGPASSWORD=${POSTGRES_PASSWORD:-postgres} psql -h localhost -U postgres -d postgres -c "
SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication;
" 2>/dev/null || echo "  Could not connect to PostgreSQL or no replicas connected"
echo ""

# Check if node is primary or replica
echo "Node Role Check:"
echo "----------------"
PRIMARY_CHECK=$(curl -sf -o /dev/null -w '%{http_code}' "http://${PATRONI_HOST}:${PATRONI_PORT}/primary" 2>/dev/null)
REPLICA_CHECK=$(curl -sf -o /dev/null -w '%{http_code}' "http://${PATRONI_HOST}:${PATRONI_PORT}/replica" 2>/dev/null)

if [ "$PRIMARY_CHECK" = "200" ]; then
    echo "  This node is the PRIMARY"
elif [ "$REPLICA_CHECK" = "200" ]; then
    echo "  This node is a REPLICA"
else
    echo "  Node role could not be determined"
fi
echo ""

echo "========================================"
