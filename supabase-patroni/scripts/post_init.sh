#!/bin/bash
# =============================================================================
# Patroni Post-Initialization Script
# This script runs after the PostgreSQL cluster is bootstrapped
# =============================================================================

set -e

PGVERSION=${PGVERSION:-16}
PGBIN="/usr/lib/postgresql/$PGVERSION/bin"

echo "=== Running Supabase PostgreSQL post-initialization ==="

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if $PGBIN/pg_isready -h localhost -p 5432 > /dev/null 2>&1; then
        echo "PostgreSQL is ready"
        break
    fi
    echo "Waiting for PostgreSQL to be ready... ($i/30)"
    sleep 1
done

# Run the Supabase initialization script if it exists
INIT_SCRIPT="/scripts/init-supabase-db.sql"
if [ -f "$INIT_SCRIPT" ]; then
    echo "Running Supabase database initialization script..."
    
    # Get the superuser password from environment
    PGPASSWORD="${PATRONI_SUPERUSER_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}"
    export PGPASSWORD
    
    # Run the initialization script
    $PGBIN/psql -h localhost -p 5432 -U postgres -d postgres -f "$INIT_SCRIPT" 2>&1 || {
        echo "Warning: Some parts of init script may have failed, but continuing..."
    }
    
    unset PGPASSWORD
    echo "Supabase database initialization complete"
else
    echo "No Supabase init script found at $INIT_SCRIPT, skipping..."
fi

# Create additional schemas if specified
if [ -n "$PATRONI_ADDITIONAL_SCHEMAS" ]; then
    echo "Creating additional schemas: $PATRONI_ADDITIONAL_SCHEMAS"
    IFS=',' read -ra SCHEMAS <<< "$PATRONI_ADDITIONAL_SCHEMAS"
    for schema in "${SCHEMAS[@]}"; do
        $PGBIN/psql -h localhost -p 5432 -U postgres -d postgres -c "CREATE SCHEMA IF NOT EXISTS $schema;" || true
    done
fi

# Run any custom post-init scripts
CUSTOM_SCRIPTS_DIR="/scripts/post_init.d"
if [ -d "$CUSTOM_SCRIPTS_DIR" ]; then
    echo "Running custom post-init scripts from $CUSTOM_SCRIPTS_DIR..."
    for script in "$CUSTOM_SCRIPTS_DIR"/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            echo "Running: $script"
            "$script"
        fi
    done
fi

echo "=== Post-initialization complete ==="
