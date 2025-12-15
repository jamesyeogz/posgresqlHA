#!/bin/bash
# =============================================================================
# Start PostgreSQL HA Cluster
# =============================================================================
# This script starts all components of the PostgreSQL HA cluster
# Run this on each VM with the appropriate node number
#
# Usage: ./start-cluster.sh [node_number] [--with-haproxy]
#   node_number: 1, 2, or 3 (defaults to 1)
#   --with-haproxy: Also start HAProxy (optional)
#
# Examples:
#   ./start-cluster.sh 1              # Start VM1 services
#   ./start-cluster.sh 2              # Start VM2 services
#   ./start-cluster.sh 1 --with-haproxy  # Start VM1 + HAProxy
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
WITH_HAPROXY=false

for arg in "$@"; do
    case $arg in
        --with-haproxy)
            WITH_HAPROXY=true
            shift
            ;;
    esac
done

# Validate node number
if [[ ! "$NODE" =~ ^[1-3]$ ]]; then
    echo -e "${RED}Error: Node number must be 1, 2, or 3${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Starting PostgreSQL HA Cluster - Node $NODE${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if env file exists
ENV_FILE="$PROJECT_DIR/.env.vm$NODE"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.vm$NODE.yml"

if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}Error: Environment file not found: $ENV_FILE${NC}"
    echo -e "${YELLOW}Please copy .env.vm$NODE.example to .env.vm$NODE and configure it${NC}"
    exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}Error: Compose file not found: $COMPOSE_FILE${NC}"
    exit 1
fi

# Pull images
echo -e "${YELLOW}Pulling latest images...${NC}"
docker-compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

# Start services
echo -e "${YELLOW}Starting etcd and Patroni services...${NC}"
docker-compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

# Wait for etcd
echo -e "${YELLOW}Waiting for etcd to be healthy...${NC}"
sleep 5
for i in {1..30}; do
    if docker exec "etcd$NODE" etcdctl endpoint health 2>/dev/null | grep -q "is healthy"; then
        echo -e "${GREEN}✓ etcd$NODE is healthy${NC}"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo -e "${RED}✗ etcd$NODE failed to become healthy${NC}"
        exit 1
    fi
    echo -e "  Waiting... ($i/30)"
    sleep 2
done

# Wait for Patroni
echo -e "${YELLOW}Waiting for Patroni to be ready...${NC}"
sleep 10
for i in {1..60}; do
    if docker exec "patroni$NODE" pg_isready -h localhost -p 5432 2>/dev/null; then
        echo -e "${GREEN}✓ patroni$NODE PostgreSQL is ready${NC}"
        break
    fi
    if [[ $i -eq 60 ]]; then
        echo -e "${RED}✗ patroni$NODE failed to become ready${NC}"
        echo -e "${YELLOW}Check logs with: docker logs patroni$NODE${NC}"
        exit 1
    fi
    echo -e "  Waiting... ($i/60)"
    sleep 3
done

# Start HAProxy if requested
if [[ "$WITH_HAPROXY" == true ]]; then
    HAPROXY_ENV="$PROJECT_DIR/.env.haproxy"
    HAPROXY_COMPOSE="$PROJECT_DIR/docker-compose.haproxy.yml"
    
    if [[ -f "$HAPROXY_ENV" && -f "$HAPROXY_COMPOSE" ]]; then
        echo -e "${YELLOW}Starting HAProxy...${NC}"
        docker-compose --env-file "$HAPROXY_ENV" -f "$HAPROXY_COMPOSE" up -d
        echo -e "${GREEN}✓ HAProxy started${NC}"
    else
        echo -e "${RED}HAProxy config files not found, skipping...${NC}"
    fi
fi

# Show status
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Cluster Node $NODE Started Successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Show running containers
echo -e "${YELLOW}Running containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "etcd|patroni|haproxy"

echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  Check cluster status: docker exec patroni$NODE patronictl list"
echo -e "  Check etcd health:    docker exec etcd$NODE etcdctl endpoint health --cluster"
echo -e "  View Patroni logs:    docker logs -f patroni$NODE"
echo -e "  View etcd logs:       docker logs -f etcd$NODE"
