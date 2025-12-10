#!/bin/bash
# Generate HAProxy config with actual VM IPs
# Usage: ./scripts/generate-haproxy-config.sh

set -e

# Check required environment variables
if [ -z "$NODE1_IP" ] || [ -z "$NODE2_IP" ] || [ -z "$NODE3_IP" ]; then
    echo "ERROR: Please set NODE1_IP, NODE2_IP, and NODE3_IP environment variables"
    echo ""
    echo "Example:"
    echo "  export NODE1_IP=192.168.1.10"
    echo "  export NODE2_IP=192.168.1.11"
    echo "  export NODE3_IP=192.168.1.12"
    echo "  ./scripts/generate-haproxy-config.sh"
    exit 1
fi

echo "Generating HAProxy config with:"
echo "  NODE1_IP: $NODE1_IP"
echo "  NODE2_IP: $NODE2_IP"
echo "  NODE3_IP: $NODE3_IP"

cat > haproxy/haproxy.cfg << EOF
# =============================================================================
# HAProxy Configuration for PostgreSQL HA Cluster with Patroni
# Generated with NODE1_IP=$NODE1_IP, NODE2_IP=$NODE2_IP, NODE3_IP=$NODE3_IP
# =============================================================================

global
    maxconn 1000
    log stdout format raw local0 info
    stats socket /var/run/haproxy.sock mode 660 level admin
    stats timeout 30s

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    option redispatch
    retries 3
    timeout connect 10s
    timeout client 30m
    timeout server 30m
    timeout check 5s

# Stats Dashboard - http://<haproxy-ip>:7000/stats (admin/admin123)
listen stats
    bind *:7000
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats show-legends
    stats show-node
    stats auth admin:admin123
    stats admin if TRUE

# PostgreSQL Primary (Read/Write) - Port 5000
listen postgres_primary
    bind *:5000
    mode tcp
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions

    server patroni1 $NODE1_IP:5432 maxconn 100 check port 8008
    server patroni2 $NODE2_IP:5432 maxconn 100 check port 8008
    server patroni3 $NODE3_IP:5432 maxconn 100 check port 8008

# PostgreSQL Replicas (Read-Only) - Port 5001
listen postgres_replicas
    bind *:5001
    mode tcp
    balance roundrobin
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions

    server patroni1 $NODE1_IP:5432 maxconn 100 check port 8008
    server patroni2 $NODE2_IP:5432 maxconn 100 check port 8008
    server patroni3 $NODE3_IP:5432 maxconn 100 check port 8008

# PostgreSQL Any Node - Port 5002
listen postgres_any
    bind *:5002
    mode tcp
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions

    server patroni1 $NODE1_IP:5432 maxconn 100 check port 8008
    server patroni2 $NODE2_IP:5432 maxconn 100 check port 8008
    server patroni3 $NODE3_IP:5432 maxconn 100 check port 8008
EOF

echo ""
echo "Generated haproxy/haproxy.cfg successfully!"
echo ""
echo "Now run HAProxy:"
echo "  docker-compose -f docker-compose.haproxy.yml up -d"
echo ""
echo "Then check:"
echo "  - Stats: http://localhost:7000/stats"
echo "  - Primary: curl http://$NODE1_IP:8008/primary"

