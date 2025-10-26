#!/bin/bash
set -e

# Wait for etcd to be available (from Kubernetes)
echo "Waiting for etcd to be available at ${ETCD_HOSTS}..."
IFS=',' read -ra ETCD_ARRAY <<< "$ETCD_HOSTS"
for etcd_host in "${ETCD_ARRAY[@]}"; do
    echo "Checking etcd at $etcd_host..."
    until curl -f "http://$etcd_host/health" 2>/dev/null; do
        echo "Waiting for etcd at $etcd_host..."
        sleep 2
    done
done

echo "etcd is available, starting Patroni..."

# Create pgpass file
echo "*:*:*:postgres:${POSTGRES_PASSWORD}" > /tmp/pgpass
echo "*:*:*:replicator:${REPLICATION_PASSWORD}" >> /tmp/pgpass
chmod 600 /tmp/pgpass

# Start Patroni
exec patroni /etc/patroni/patroni.yml
