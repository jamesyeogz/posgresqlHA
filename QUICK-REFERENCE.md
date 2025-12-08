# Quick Reference - PostgreSQL HA Cluster

## Connection Strings

### Via HAProxy (Recommended)

```bash
# Primary (Read/Write)
psql -h <HAPROXY_IP> -p 5000 -U postgres -d postgres

# Replica (Read-Only)
psql -h <HAPROXY_IP> -p 5001 -U postgres -d postgres

# Connection string for applications
postgresql://postgres:<password>@<HAPROXY_IP>:5000/postgres
```

### Direct Node Access

```bash
# Development (docker-compose.dev.yml)
psql -h localhost -p 5432 -U postgres   # patroni1
psql -h localhost -p 5433 -U postgres   # patroni2
psql -h localhost -p 5434 -U postgres   # patroni3

# Production (via VM IPs)
psql -h <NODE1_IP> -p 5432 -U postgres
psql -h <NODE2_IP> -p 5432 -U postgres
psql -h <NODE3_IP> -p 5432 -U postgres
```

## Cluster Management

### Check Status

```bash
# Patroni cluster
docker exec patroni1 patronictl list

# etcd cluster
docker exec etcd1 etcdctl endpoint health --cluster
docker exec etcd1 etcdctl member list -w table
```

### Failover

```bash
# Manual failover
docker exec patroni1 patronictl failover postgres-ha --candidate patroni2 --force

# Graceful switchover
docker exec patroni1 patronictl switchover postgres-ha --candidate patroni2 --force
```

### Restart Node

```bash
# Restart Patroni (PostgreSQL will auto-recover)
docker restart patroni1

# Reinitialize a failed replica
docker exec patroni1 patronictl reinit postgres-ha patroni2 --force
```

## Useful Commands

### PostgreSQL

```bash
# Check if node is primary or replica
docker exec patroni1 psql -U postgres -c "SELECT pg_is_in_recovery();"
# Returns 'f' for primary, 't' for replica

# Check replication status (run on primary)
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check replication slots
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_replication_slots;"
```

### Patroni API

```bash
# Health check
curl http://<NODE_IP>:8008/health

# Check if primary
curl http://<NODE_IP>:8008/primary

# Check if replica
curl http://<NODE_IP>:8008/replica

# Cluster info
curl http://<NODE_IP>:8008/cluster
```

### etcd

```bash
# Cluster health
docker exec etcd1 etcdctl endpoint health --cluster

# Get Patroni leader key
docker exec etcd1 etcdctl get /postgres-ha/leader
```

## Start/Stop Commands

### Development (Single Host)

```bash
# Start everything
docker-compose -f docker-compose.dev.yml up -d

# Stop (keep data)
docker-compose -f docker-compose.dev.yml down

# Stop and remove data
docker-compose -f docker-compose.dev.yml down -v
```

### Production (Multi-VM)

```bash
# Start (on each VM)
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d

# Stop (on each VM)
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml down

# Start HAProxy
docker-compose --env-file .env.haproxy -f docker-compose.haproxy.yml up -d
```

### Helper Scripts

```bash
./scripts/start-cluster.sh 1              # Start node 1
./scripts/stop-cluster.sh 1               # Stop node 1
./scripts/cluster-status.sh               # Check status
./scripts/cluster-status.sh --watch       # Continuous monitoring
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 2379 | etcd | Client API |
| 2380 | etcd | Peer communication |
| 5432 | PostgreSQL | Database |
| 8008 | Patroni | REST API |
| 5000 | HAProxy | Primary (R/W) |
| 5001 | HAProxy | Replica (R/O) |
| 7000 | HAProxy | Stats dashboard |

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| PostgreSQL | `postgres` | `postgres` (dev) |
| Replication | `replicator` | `replicator` (dev) |
| HAProxy Stats | `admin` | `admin123` |

⚠️ **Change all passwords for production!**

## HAProxy Stats Dashboard

```
URL: http://<HAPROXY_IP>:7000/stats
User: admin
Pass: admin123
```

## Troubleshooting

```bash
# View logs
docker logs -f patroni1
docker logs -f etcd1
docker logs -f haproxy

# Check container status
docker ps | grep -E "patroni|etcd|haproxy"

# Test connectivity
docker exec patroni1 nc -zv etcd1 2379
curl http://localhost:8008/health
```
