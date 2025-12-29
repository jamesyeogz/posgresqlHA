#!/bin/bash
# =============================================================================
# Base PostgreSQL Installation Script
# Installs PostgreSQL 16 and core dependencies on Ubuntu
# Based on Zalando Spilo's approach
# =============================================================================

set -ex

export DEBIAN_FRONTEND=noninteractive
MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)"
export MAKEFLAGS

PGVERSION=${PGVERSION:-16}

echo "=== Installing PostgreSQL $PGVERSION and base dependencies ==="

# Enable universe repository
sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list || true

apt-get update

# Build packages needed for compilation
BUILD_PACKAGES=(
    build-essential
    gcc
    g++
    make
    cmake
    git
    curl
    wget
    ca-certificates
    devscripts
    debhelper
    fakeroot
    pkg-config
)

# Runtime dependencies
RUNTIME_PACKAGES=(
    libevent-2.1-7
    libevent-pthreads-2.1-7
    libbrotli1
    libcurl4
    libsodium23
    libicu70
    python3
    python3-pip
    python3-psycopg2
    python3-yaml
    python3-requests
    python3-pystache
    python3-psutil
    gnupg
    lsb-release
    locales
    runit
    dumb-init
    jq
)

# Development packages for building extensions
DEV_PACKAGES=(
    zlib1g-dev
    libssl-dev
    libkrb5-dev
    libpam0g-dev
    libcurl4-openssl-dev
    libicu-dev
    libevent-dev
    libbrotli-dev
    libsodium-dev
)

apt-get install -y "${BUILD_PACKAGES[@]}" "${RUNTIME_PACKAGES[@]}" "${DEV_PACKAGES[@]}"

# Generate locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Add PostgreSQL repository
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

apt-get update

# Configure postgresql-common to not create default cluster
mkdir -p /etc/postgresql-common
echo "create_main_cluster = false" >> /etc/postgresql-common/createcluster.conf

# Install PostgreSQL
apt-get install -y \
    "postgresql-$PGVERSION" \
    "postgresql-contrib-$PGVERSION" \
    "postgresql-server-dev-$PGVERSION" \
    "postgresql-plpython3-$PGVERSION" \
    "postgresql-$PGVERSION-cron"

# Create postgres user home directory
mkdir -p /home/postgres
chown -R postgres:postgres /home/postgres

# Set up PATH for PostgreSQL binaries
echo "export PATH=/usr/lib/postgresql/$PGVERSION/bin:\$PATH" >> /home/postgres/.bashrc

echo "=== PostgreSQL $PGVERSION base installation complete ==="
