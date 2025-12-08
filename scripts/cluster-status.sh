#!/bin/bash
# =============================================================================
# Check PostgreSQL HA Cluster Status
# =============================================================================
# This script displays the current status of all cluster components
#
# Usage: ./cluster-status.sh [--watch]
#   --watch: Continuously monitor status (refresh every 5 seconds)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
WATCH_MODE=false
for arg in "$@"; do
    case $arg in
        --watch)
            WATCH_MODE=true
            ;;
    esac
done

check_status() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         PostgreSQL HA Cluster Status                           ║${NC}"
    echo -e "${BLUE}║         $(date '+%Y-%m-%d %H:%M:%S')                                     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check Docker containers
    echo -e "${CYAN}═══ Docker Containers ═══${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -E "NAMES|etcd|patroni|haproxy" || echo "No cluster containers running"
    echo ""

    # Check etcd cluster
    echo -e "${CYAN}═══ etcd Cluster ═══${NC}"
    for node in 1 2 3; do
        if docker ps --format "{{.Names}}" | grep -q "etcd$node"; then
            health=$(docker exec "etcd$node" etcdctl endpoint health 2>&1 || echo "unhealthy")
            if echo "$health" | grep -q "is healthy"; then
                echo -e "  etcd$node: ${GREEN}●${NC} healthy"
            else
                echo -e "  etcd$node: ${RED}●${NC} unhealthy"
            fi
        else
            echo -e "  etcd$node: ${YELLOW}○${NC} not running"
        fi
    done
    echo ""

    # Check etcd cluster members
    for node in 1 2 3; do
        if docker ps --format "{{.Names}}" | grep -q "etcd$node"; then
            echo -e "${CYAN}etcd Cluster Members (from etcd$node):${NC}"
            docker exec "etcd$node" etcdctl member list -w table 2>/dev/null || echo "Could not get member list"
            break
        fi
    done
    echo ""

    # Check Patroni cluster
    echo -e "${CYAN}═══ Patroni Cluster ═══${NC}"
    for node in 1 2 3; do
        if docker ps --format "{{.Names}}" | grep -q "patroni$node"; then
            echo -e "${CYAN}Patroni Cluster Status (from patroni$node):${NC}"
            docker exec "patroni$node" patronictl list 2>/dev/null || echo "Could not get cluster status"
            break
        fi
    done
    echo ""

    # Check PostgreSQL status per node
    echo -e "${CYAN}═══ PostgreSQL Nodes ═══${NC}"
    for node in 1 2 3; do
        if docker ps --format "{{.Names}}" | grep -q "patroni$node"; then
            pg_ready=$(docker exec "patroni$node" pg_isready -h localhost -p 5432 2>&1 || echo "not ready")
            if echo "$pg_ready" | grep -q "accepting connections"; then
                role=$(docker exec "patroni$node" psql -U postgres -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END;" 2>/dev/null | tr -d ' ' || echo "unknown")
                echo -e "  patroni$node: ${GREEN}●${NC} running ($role)"
            else
                echo -e "  patroni$node: ${RED}●${NC} not accepting connections"
            fi
        else
            echo -e "  patroni$node: ${YELLOW}○${NC} not running"
        fi
    done
    echo ""

    # Check HAProxy
    echo -e "${CYAN}═══ HAProxy ═══${NC}"
    if docker ps --format "{{.Names}}" | grep -q "haproxy"; then
        echo -e "  haproxy: ${GREEN}●${NC} running"
        echo "  Stats URL: http://localhost:7000/stats"
    else
        echo -e "  haproxy: ${YELLOW}○${NC} not running"
    fi
    echo ""

    # Replication status
    echo -e "${CYAN}═══ Replication Status ═══${NC}"
    for node in 1 2 3; do
        if docker ps --format "{{.Names}}" | grep -q "patroni$node"; then
            is_primary=$(docker exec "patroni$node" psql -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
            if [[ "$is_primary" == "t" ]]; then
                echo -e "${CYAN}Replication slots (from primary patroni$node):${NC}"
                docker exec "patroni$node" psql -U postgres -c "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;" 2>/dev/null || echo "Could not get replication slots"
                echo ""
                echo -e "${CYAN}Replication connections:${NC}"
                docker exec "patroni$node" psql -U postgres -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;" 2>/dev/null || echo "Could not get replication status"
                break
            fi
        fi
    done
    
    if [[ "$WATCH_MODE" == true ]]; then
        echo ""
        echo -e "${YELLOW}Press Ctrl+C to exit watch mode${NC}"
    fi
}

if [[ "$WATCH_MODE" == true ]]; then
    while true; do
        check_status
        sleep 5
    done
else
    check_status
fi
