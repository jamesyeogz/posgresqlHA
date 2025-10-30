#!/bin/bash
set -e

# Wait for Consul to be available (agent or cluster endpoint)
CONSUL_HOST_ONLY="${CONSUL_HOST:-consul-agent}"
CONSUL_PORT="${CONSUL_PORT:-8500}"
CONSUL_TARGET="${CONSUL_HOST_ONLY}:${CONSUL_PORT}"
echo "Waiting for Consul to be available at ${CONSUL_TARGET}..."
until curl -fsS "http://${CONSUL_TARGET}/v1/status/leader" | grep -q '"'; do
    echo "Waiting for Consul leader at ${CONSUL_TARGET}..."
    sleep 2
done

echo "Consul is available, starting Patroni..."

# Fix permissions on data directories
chown -R postgres:postgres /home/postgres/pgdata
chmod -R 700 /home/postgres/pgdata/pgroot/data
chown -R postgres:postgres /var/run/postgresql

# Create pgpass file
echo "*:*:*:postgres:${POSTGRES_PASSWORD}" > /tmp/pgpass
echo "*:*:*:replicator:${REPLICATION_PASSWORD}" >> /tmp/pgpass
chmod 600 /tmp/pgpass
chown postgres:postgres /tmp/pgpass

# Substitute environment variables in patroni.yml template
envsubst < /etc/patroni/patroni.yml > /tmp/patroni.yml
chown postgres:postgres /tmp/patroni.yml

# Start Patroni as postgres user with processed config
exec gosu postgres patroni /tmp/patroni.yml
