#!/bin/bash
# =============================================================================
# Build Script for Supabase-Compatible Patroni Image
# =============================================================================
# Usage: ./docker/build.sh [tag]
# Example: ./docker/build.sh supabase-patroni:v1.0
# =============================================================================

set -e

# Default tag
TAG="${1:-supabase-patroni:latest}"

echo "=============================================="
echo "Building Supabase-Patroni Docker Image"
echo "Tag: $TAG"
echo "=============================================="

# Navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Build the image
docker build \
    -t "$TAG" \
    -f docker/Dockerfile.supabase-patroni \
    .

echo "=============================================="
echo "Build completed successfully!"
echo "Image: $TAG"
echo "=============================================="
echo ""
echo "To push to a registry:"
echo "  docker tag $TAG your-registry/$TAG"
echo "  docker push your-registry/$TAG"
echo ""
echo "To test locally:"
echo "  docker run --rm $TAG postgres --version"
echo ""

