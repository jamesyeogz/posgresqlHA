#!/bin/bash
# =============================================================================
# Stop PostgreSQL HA Cluster
# =============================================================================
# This script stops all components of the PostgreSQL HA cluster
#
# Usage: ./stop-cluster.sh [node_number] [--all] [--with-haproxy] [--remove-volumes]
#   node_number: 1, 2, or 3 (defaults to 1)
#   --all: Stop all nodes (ignores node_number)
#   --with-haproxy: Also stop HAProxy
#   --remove-volumes: Remove data volumes (WARNING: destroys data!)
#
# Examples:
#   ./stop-cluster.sh 1                # Stop VM1 services
#   ./stop-cluster.sh --all            # Stop all nodes
#   ./stop-cluster.sh 1 --remove-volumes  # Stop and remove data
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
NODE=${1:-1}
STOP_ALL=false
WITH_HAPROXY=false
REMOVE_VOLUMES=false

for arg in "$@"; do
    case $arg in
        --all)
            STOP_ALL=true
            ;;
        --with-haproxy)
            WITH_HAPROXY=true
            ;;
        --remove-volumes)
            REMOVE_VOLUMES=true
            ;;
    esac
done

# Validate node number
if [[ "$STOP_ALL" == false && ! "$NODE" =~ ^[1-3]$ ]]; then
    echo -e "${RED}Error: Node number must be 1, 2, or 3${NC}"
    exit 1
fi

# Warning for volume removal
if [[ "$REMOVE_VOLUMES" == true ]]; then
    echo -e "${RED}WARNING: --remove-volumes will DELETE ALL DATA!${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${YELLOW}Aborted.${NC}"
        exit 0
    fi
fi

stop_node() {
    local node=$1
    local env_file="$PROJECT_DIR/.env.vm$node"
    local compose_file="$PROJECT_DIR/docker-compose.vm$node.yml"
    
    if [[ -f "$compose_file" ]]; then
        echo -e "${YELLOW}Stopping Node $node...${NC}"
        
        if [[ "$REMOVE_VOLUMES" == true ]]; then
            docker-compose --env-file "$env_file" -f "$compose_file" down -v 2>/dev/null || true
        else
            docker-compose --env-file "$env_file" -f "$compose_file" down 2>/dev/null || true
        fi
        
        echo -e "${GREEN}✓ Node $node stopped${NC}"
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Stopping PostgreSQL HA Cluster${NC}"
echo -e "${BLUE}========================================${NC}"

# Stop HAProxy if requested
if [[ "$WITH_HAPROXY" == true ]]; then
    haproxy_env="$PROJECT_DIR/.env.haproxy"
    haproxy_compose="$PROJECT_DIR/docker-compose.haproxy.yml"
    
    if [[ -f "$haproxy_compose" ]]; then
        echo -e "${YELLOW}Stopping HAProxy...${NC}"
        docker-compose --env-file "$haproxy_env" -f "$haproxy_compose" down 2>/dev/null || true
        echo -e "${GREEN}✓ HAProxy stopped${NC}"
    fi
fi

# Stop nodes
if [[ "$STOP_ALL" == true ]]; then
    for node in 1 2 3; do
        stop_node $node
    done
else
    stop_node $NODE
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cluster stopped successfully${NC}"
echo -e "${GREEN}========================================${NC}"

# Show remaining containers
remaining=$(docker ps --format "{{.Names}}" | grep -E "etcd|patroni|haproxy" || true)
if [[ -n "$remaining" ]]; then
    echo ""
    echo -e "${YELLOW}Remaining cluster containers:${NC}"
    echo "$remaining"
fi
