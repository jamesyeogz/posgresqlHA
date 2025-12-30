#!/bin/bash
# =============================================================================
# Entrypoint for Supabase-Patroni
# =============================================================================
set -e

echo "=== Supabase-Patroni Starting ==="
echo "Node: ${PATRONI_NAME:-patroni1}"
echo "Scope: ${PATRONI_SCOPE:-supabase-ha}"

# Wait for etcd
wait_for_etcd() {
    local host=$(echo ${PATRONI_ETCD3_HOSTS:-etcd1:2379} | cut -d',' -f1 | cut -d':' -f1)
    local port=$(echo ${PATRONI_ETCD3_HOSTS:-etcd1:2379} | cut -d',' -f1 | cut -d':' -f2)
    
    echo "Waiting for etcd at $host:$port..."
    for i in $(seq 1 60); do
        if nc -z $host $port 2>/dev/null; then
            echo "etcd is ready!"
            return 0
        fi
        echo "Attempt $i/60..."
        sleep 2
    done
    echo "ERROR: etcd not available"
    exit 1
}

# Generate patroni.yml from template
generate_config() {
    echo "Generating Patroni config..."
    
    cp /etc/patroni/patroni.yml.template /etc/patroni/patroni.yml
    
    sed -i "s|\${PATRONI_SCOPE}|${PATRONI_SCOPE:-supabase-ha}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_NAME}|${PATRONI_NAME:-patroni1}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_RESTAPI_LISTEN}|${PATRONI_RESTAPI_LISTEN:-0.0.0.0:8008}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_RESTAPI_CONNECT_ADDRESS}|${PATRONI_RESTAPI_CONNECT_ADDRESS:-localhost:8008}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_ETCD3_HOSTS}|${PATRONI_ETCD3_HOSTS:-etcd1:2379}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_POSTGRESQL_LISTEN}|${PATRONI_POSTGRESQL_LISTEN:-0.0.0.0:5432}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_POSTGRESQL_CONNECT_ADDRESS}|${PATRONI_POSTGRESQL_CONNECT_ADDRESS:-localhost:5432}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_POSTGRESQL_DATA_DIR}|${PATRONI_POSTGRESQL_DATA_DIR:-/home/postgres/pgdata/data}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_SUPERUSER_USERNAME}|${PATRONI_SUPERUSER_USERNAME:-postgres}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_SUPERUSER_PASSWORD}|${PATRONI_SUPERUSER_PASSWORD:-postgres}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_REPLICATION_USERNAME}|${PATRONI_REPLICATION_USERNAME:-replicator}|g" /etc/patroni/patroni.yml
    sed -i "s|\${PATRONI_REPLICATION_PASSWORD}|${PATRONI_REPLICATION_PASSWORD:-replicator}|g" /etc/patroni/patroni.yml
    
    # Inject JWT settings if provided
    if [ -n "$JWT_SECRET" ]; then
        sed -i "s|\${JWT_SECRET}|${JWT_SECRET}|g" /etc/patroni/patroni.yml
    fi
    if [ -n "$JWT_EXP" ]; then
        sed -i "s|\${JWT_EXP}|${JWT_EXP}|g" /etc/patroni/patroni.yml
    fi
}

wait_for_etcd
generate_config

echo "Starting Patroni..."
exec "$@"

