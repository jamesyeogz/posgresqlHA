#!/bin/bash
# =============================================================================
# Supabase Extensions Installation Script
# Installs PostgreSQL extensions required by Supabase
# =============================================================================

set -ex

export DEBIAN_FRONTEND=noninteractive
MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)"
export MAKEFLAGS

PGVERSION=${PGVERSION:-16}
PG_CONFIG="/usr/lib/postgresql/$PGVERSION/bin/pg_config"

echo "=== Installing Supabase Extensions for PostgreSQL $PGVERSION ==="

# Ensure build tools are available
apt-get update
apt-get install -y \
    build-essential \
    git \
    "postgresql-server-dev-$PGVERSION" \
    libsodium-dev \
    libcurl4-openssl-dev

cd /tmp

# -----------------------------------------------------------------------------
# pgvector - AI/ML vector similarity search
# -----------------------------------------------------------------------------
echo "Installing pgvector..."
git clone --branch v0.7.4 --depth 1 https://github.com/pgvector/pgvector.git
cd pgvector
make PG_CONFIG="$PG_CONFIG"
make PG_CONFIG="$PG_CONFIG" install
cd /tmp && rm -rf pgvector

# -----------------------------------------------------------------------------
# pgsodium - Encryption (required for Supabase Vault)
# -----------------------------------------------------------------------------
echo "Installing pgsodium..."
git clone --branch v3.1.9 --depth 1 https://github.com/michelp/pgsodium.git
cd pgsodium
make PG_CONFIG="$PG_CONFIG"
make PG_CONFIG="$PG_CONFIG" install
cd /tmp && rm -rf pgsodium

# -----------------------------------------------------------------------------
# pgjwt - JWT generation/verification (required for Supabase Auth)
# -----------------------------------------------------------------------------
echo "Installing pgjwt..."
git clone --depth 1 https://github.com/michelp/pgjwt.git
cd pgjwt
make PG_CONFIG="$PG_CONFIG" install
cd /tmp && rm -rf pgjwt

# -----------------------------------------------------------------------------
# http - HTTP client extension
# -----------------------------------------------------------------------------
echo "Installing http extension..."
git clone --branch v1.6.0 --depth 1 https://github.com/pramsey/pgsql-http.git
cd pgsql-http
make PG_CONFIG="$PG_CONFIG"
make PG_CONFIG="$PG_CONFIG" install
cd /tmp && rm -rf pgsql-http

# -----------------------------------------------------------------------------
# pg_hashids - Short unique IDs
# -----------------------------------------------------------------------------
echo "Installing pg_hashids..."
git clone --depth 1 https://github.com/iCyberon/pg_hashids.git
cd pg_hashids
make PG_CONFIG="$PG_CONFIG"
make PG_CONFIG="$PG_CONFIG" install
cd /tmp && rm -rf pg_hashids

# -----------------------------------------------------------------------------
# pg_stat_statements - Query monitoring (usually already installed with contrib)
# -----------------------------------------------------------------------------
echo "Verifying pg_stat_statements..."
ls -la /usr/lib/postgresql/$PGVERSION/lib/pg_stat_statements.so || echo "pg_stat_statements not found, should be in contrib"

# -----------------------------------------------------------------------------
# Additional extensions (optional, uncomment if needed)
# -----------------------------------------------------------------------------

# pg_graphql - GraphQL support (requires Rust)
# echo "Installing pg_graphql..."
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# source $HOME/.cargo/env
# git clone --depth 1 https://github.com/supabase/pg_graphql.git
# cd pg_graphql
# cargo build --release
# cd /tmp && rm -rf pg_graphql

# pg_jsonschema - JSON Schema validation (requires Rust)
# Similar to pg_graphql, requires Rust build environment

# Clean up
echo "Cleaning up build dependencies..."
apt-get remove -y build-essential git "postgresql-server-dev-$PGVERSION"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "=== Supabase Extensions installation complete ==="

# List installed extensions
echo "Installed extensions:"
ls -la /usr/lib/postgresql/$PGVERSION/lib/*.so 2>/dev/null | head -30 || true
ls -la /usr/share/postgresql/$PGVERSION/extension/*.control 2>/dev/null | head -30 || true
