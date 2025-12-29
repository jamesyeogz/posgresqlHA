#!/bin/sh
# =============================================================================
# Supabase Patroni Launch Script
# Main entry point for the Docker container
# Based on Zalando Spilo's launch.sh
# =============================================================================

set -e

# Initialize with dumb-init for proper signal handling
if [ "$1" = "init" ]; then
    exec /usr/bin/dumb-init -c --rewrite 1:0 -- /bin/sh /launch.sh
fi

echo "========================================"
echo "Starting Supabase Patroni Container"
echo "========================================"

# Set environment defaults
export PGVERSION=${PGVERSION:-16}
export PGHOME=${PGHOME:-/home/postgres}
export RW_DIR=${RW_DIR:-/run}
export LC_ALL=${LC_ALL:-en_US.UTF-8}
export LANG=${LANG:-en_US.UTF-8}
export PATH="/usr/lib/postgresql/$PGVERSION/bin:$PATH"

# Define directories
PGROOT="$PGHOME/pgdata"
PGDATA="$PGROOT/data"
PGLOG="$PGROOT/pg_log"

export PGROOT PGDATA PGLOG

# Configure system settings if running as root
if [ "$(id -u)" -eq 0 ]; then
    # Optimize dirty page handling for databases
    sysctl -w vm.dirty_background_bytes=67108864 > /dev/null 2>&1 || true
    sysctl -w vm.dirty_bytes=134217728 > /dev/null 2>&1 || true
fi

# Create required directories
echo "Creating directories..."
mkdir -p "$PGLOG" "$PGDATA" "$RW_DIR/postgresql" "$RW_DIR/tmp" "$RW_DIR/certs" "$RW_DIR/service"
mkdir -p /var/run/postgresql

# Fix ownership if running as root
if [ "$(id -u)" -eq 0 ]; then
    chown -R postgres:postgres "$PGROOT" "$RW_DIR/certs" "$RW_DIR/postgresql" /var/run/postgresql
    chmod -R go-w "$PGROOT"
    chmod 0700 "$PGDATA"
    chmod 01777 "$RW_DIR/tmp"
else
    # Update passwd file with current user ID (for Kubernetes/OpenShift)
    if [ -w /etc/passwd ]; then
        sed -e "s/^postgres:x:[^:]*:[^:]*:/postgres:x:$(id -u):$(id -g):/" /etc/passwd > "$RW_DIR/tmp/passwd"
        cat "$RW_DIR/tmp/passwd" > /etc/passwd
        rm "$RW_DIR/tmp/passwd"
    fi
fi

# Generate Patroni configuration
echo "Generating Patroni configuration..."
python3 /scripts/configure_patroni.py --force || {
    echo "ERROR: Failed to generate Patroni configuration"
    exit 1
}

# Verify configuration was created
PATRONI_CONFIG="$RW_DIR/patroni.yml"
if [ ! -f "$PATRONI_CONFIG" ]; then
    echo "ERROR: Patroni configuration not found at $PATRONI_CONFIG"
    exit 1
fi

echo "Patroni configuration generated at: $PATRONI_CONFIG"

# Print configuration summary (without sensitive data)
echo "Configuration summary:"
echo "  - Scope: $(grep -m1 'scope:' "$PATRONI_CONFIG" | awk '{print $2}')"
echo "  - Node Name: $(grep -m1 'name:' "$PATRONI_CONFIG" | awk '{print $2}')"
echo "  - PostgreSQL Version: $PGVERSION"
echo "  - Data Directory: $PGDATA"

# Set up runit services
echo "Setting up services..."
mkdir -p /etc/service
if [ -d /etc/runit/runsvdir/default/patroni ]; then
    ln -sf /etc/runit/runsvdir/default/patroni /etc/service/patroni
elif [ -d /runit/patroni ]; then
    ln -sf /runit/patroni /etc/service/patroni
fi

# Ensure service directories exist for runit
mkdir -p "$RW_DIR/supervise/patroni"

# Signal handler for graceful shutdown
sv_stop() {
    echo "Received shutdown signal, stopping services..."
    sv -w 86400 stop patroni 2>/dev/null || true
    sv -w 86400 stop /etc/service/* 2>/dev/null || true
    exit 0
}

trap sv_stop TERM QUIT INT

# Check if we should run in foreground mode (for debugging)
if [ "$PATRONI_FOREGROUND" = "true" ]; then
    echo "Running Patroni in foreground mode..."
    exec su postgres -c "patroni $PATRONI_CONFIG"
fi

# Start runit service supervisor
echo "Starting runit service supervisor..."
if [ -d /etc/service ]; then
    /usr/bin/runsvdir -P /etc/service &
    RUNSVDIR_PID=$!
    
    echo "Services started. Waiting for Patroni..."
    
    # Wait for Patroni to be ready
    sleep 5
    
    # Keep container running
    wait $RUNSVDIR_PID
else
    echo "ERROR: /etc/service directory not found"
    echo "Running Patroni directly..."
    exec su postgres -c "patroni $PATRONI_CONFIG"
fi
