#!/bin/bash
# =============================================================================
# Build Script for Supabase Patroni Image
# =============================================================================

set -e

# Default values
IMAGE_NAME="${1:-supabase-patroni}"
IMAGE_TAG="${2:-latest}"
PGVERSION="${3:-16}"

echo "========================================"
echo "Building Supabase Patroni Image"
echo "========================================"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  PostgreSQL Version: ${PGVERSION}"
echo "========================================"
echo ""

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build the image
docker build \
    --build-arg PGVERSION="${PGVERSION}" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

echo ""
echo "========================================"
echo "Build complete!"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "To run the image:"
echo "  docker run -d \\"
echo "    -e PATRONI_NAME=node1 \\"
echo "    -e PATRONI_SCOPE=supabase-ha \\"
echo "    -e PATRONI_ETCD_HOSTS=etcd1:2379 \\"
echo "    -e POSTGRES_PASSWORD=your_password \\"
echo "    -e REPLICATION_PASSWORD=repl_password \\"
echo "    -p 5432:5432 -p 8008:8008 \\"
echo "    ${IMAGE_NAME}:${IMAGE_TAG}"
echo "========================================"
