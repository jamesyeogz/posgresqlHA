#!/bin/bash
set -e

# Wait for Consul to be available (agent or cluster endpoint)
CONSUL_TARGET="${CONSUL_HOST:-consul-agent:8500}"
echo "Waiting for Consul to be available at ${CONSUL_TARGET}..."
until curl -fsS "http://${CONSUL_TARGET}/v1/status/leader" | grep -q '"'; do
    echo "Waiting for Consul leader at ${CONSUL_TARGET}..."
    sleep 2
done

echo "Consul is available, starting Patroni..."

# Create pgpass file
echo "*:*:*:postgres:${POSTGRES_PASSWORD}" > /tmp/pgpass
echo "*:*:*:replicator:${REPLICATION_PASSWORD}" >> /tmp/pgpass
chmod 600 /tmp/pgpass

# Start Patroni
exec patroni /etc/patroni/patroni.yml
