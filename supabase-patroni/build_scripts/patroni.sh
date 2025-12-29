#!/bin/bash
# =============================================================================
# Patroni Installation Script
# Installs Patroni with etcd, consul, and kubernetes support
# Based on Zalando Spilo's approach
# =============================================================================

set -ex

export DEBIAN_FRONTEND=noninteractive

PATRONI_VERSION=${PATRONI_VERSION:-4.0.4}

echo "=== Installing Patroni $PATRONI_VERSION ==="

# Build packages needed for Python compilation
BUILD_PACKAGES=(
    python3-pip
    python3-wheel
    python3-dev
    git
)

apt-get update

# Install Patroni dependencies from Ubuntu packages where available
apt-get install -y "${BUILD_PACKAGES[@]}" \
    python3-etcd \
    python3-consul \
    python3-kazoo \
    python3-boto3 \
    python3-botocore \
    python3-cachetools \
    python3-cffi \
    python3-gevent \
    python3-pyasn1-modules \
    python3-rsa \
    python3-s3transfer \
    python3-dnspython \
    python3-urllib3 \
    python3-certifi \
    python3-chardet \
    python3-idna \
    python3-six

# Upgrade pip
pip3 install --upgrade pip setuptools wheel

# Install Patroni with all DCS backends (etcd, consul, zookeeper, kubernetes)
pip3 install "patroni[etcd,etcd3,consul,zookeeper,kubernetes]==$PATRONI_VERSION"

# Install additional Python dependencies
pip3 install \
    python-dateutil \
    click \
    prettytable \
    ydiff

# Verify Patroni installation
patroni --version
patronictl --version

# Create Patroni directories
mkdir -p /var/lib/patroni
mkdir -p /etc/patroni
mkdir -p /run/patroni

chown -R postgres:postgres /var/lib/patroni /etc/patroni /run/patroni

# Clean up build packages
apt-get remove -y python3-dev git
apt-get autoremove -y
apt-get clean

echo "=== Patroni $PATRONI_VERSION installation complete ==="
