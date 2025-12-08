# Docker-Only Setup Guide

This guide explains how to deploy the PostgreSQL HA cluster using Docker (no Kubernetes required).

## Quick Reference

| Setup Type | Files | Use Case |
|------------|-------|----------|
| **Multi-VM Production** | `docker-compose.vm1.yml`, `vm2`, `vm3` | Production across 3 VMs |
| **Single-Host Dev** | `docker-compose.dev.yml` | Local development/testing |
| **HAProxy Only** | `docker-compose.haproxy.yml` | Separate load balancer |

## Components Used

| Component | Docker Image | Version |
|-----------|--------------|---------|
| etcd | `quay.io/coreos/etcd` | v3.5.11 |
| Patroni/PostgreSQL | `ghcr.io/zalando/spilo-16` | 3.2-p2 |
| HAProxy | `haproxy` | 2.9-alpine |

**No custom images are built** - all images are pulled from public registries.

---

## Option 1: Single-Host Development Setup

Perfect for local development and testing on your laptop.

### Start Everything

```bash
# Start the entire cluster (etcd + patroni + haproxy)
docker-compose -f docker-compose.dev.yml up -d

# Watch the logs
docker-compose -f docker-compose.dev.yml logs -f
```

### Connection Endpoints

| Endpoint | Port | Purpose |
|----------|------|---------|
| Primary (R/W) | `localhost:5000` | Write operations |
| Replica (R/O) | `localhost:5001` | Read operations |
| Direct patroni1 | `localhost:5432` | Direct access |
| Direct patroni2 | `localhost:5433` | Direct access |
| Direct patroni3 | `localhost:5434` | Direct access |
| HAProxy Stats | `localhost:7000/stats` | Dashboard |

### Test Connection

```bash
# Via HAProxy (primary)
psql -h localhost -p 5000 -U postgres -d postgres

# Via HAProxy (replica)
psql -h localhost -p 5001 -U postgres -d postgres

# Check cluster status
docker exec patroni1 patronictl list
```

### Stop Everything

```bash
# Stop without removing data
docker-compose -f docker-compose.dev.yml down

# Stop and remove all data
docker-compose -f docker-compose.dev.yml down -v
```

---

## Option 2: Multi-VM Production Setup

Deploy across 3 separate VMs for production high availability.

### Prerequisites

1. 3 VMs with Docker and Docker Compose installed
2. Network connectivity between all VMs
3. Firewall ports open (2379, 2380, 5432, 8008)

### Step 1: Configure Environment Files

Copy the project to each VM and edit the `.env.vmX` file:

**On VM1:**
```bash
vim .env.vm1

# Update these values:
NODE1_IP=<actual-vm1-ip>
NODE2_IP=<actual-vm2-ip>
NODE3_IP=<actual-vm3-ip>
POSTGRES_PASSWORD=<secure-password>
REPLICATION_PASSWORD=<secure-password>
```

**On VM2:**
```bash
vim .env.vm2
# Same IP values as VM1
```

**On VM3:**
```bash
vim .env.vm3
# Same IP values as VM1
```

### Step 2: Update HAProxy Config

Edit `haproxy/haproxy.cfg` and replace the placeholder IPs:
```
192.168.1.101 → <actual-vm1-ip>
192.168.1.102 → <actual-vm2-ip>
192.168.1.103 → <actual-vm3-ip>
```

### Step 3: Start Cluster

**Start all 3 nodes within 60 seconds** (important for etcd quorum):

```bash
# On VM1
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d

# On VM2
docker-compose --env-file .env.vm2 -f docker-compose.vm2.yml up -d

# On VM3
docker-compose --env-file .env.vm3 -f docker-compose.vm3.yml up -d
```

### Step 4: Start HAProxy

On any VM (or a dedicated load balancer):

```bash
docker-compose --env-file .env.haproxy -f docker-compose.haproxy.yml up -d
```

### Step 5: Verify Cluster

```bash
# Check etcd cluster
docker exec etcd1 etcdctl endpoint health --cluster

# Check Patroni cluster
docker exec patroni1 patronictl list

# Expected output:
# + Cluster: postgres-ha ------+---------+---------+----+-----------+
# | Member    | Host          | Role    | State   | TL | Lag in MB |
# +-----------+---------------+---------+---------+----+-----------+
# | patroni1  | 192.168.1.101 | Leader  | running |  1 |           |
# | patroni2  | 192.168.1.102 | Replica | running |  1 |         0 |
# | patroni3  | 192.168.1.103 | Replica | running |  1 |         0 |
# +-----------+---------------+---------+---------+----+-----------+
```

---

## Helper Scripts

Located in the `scripts/` directory:

```bash
# Start a node
./scripts/start-cluster.sh 1              # Start VM1
./scripts/start-cluster.sh 2              # Start VM2
./scripts/start-cluster.sh 1 --with-haproxy

# Stop a node
./scripts/stop-cluster.sh 1               # Stop VM1
./scripts/stop-cluster.sh --all           # Stop all nodes
./scripts/stop-cluster.sh 1 --remove-volumes  # Remove data too

# Check status
./scripts/cluster-status.sh               # One-time check
./scripts/cluster-status.sh --watch       # Continuous monitoring
```

---

## Common Operations

### Failover

```bash
# Manual failover to specific node
docker exec patroni1 patronictl failover postgres-ha --candidate patroni2 --force

# Graceful switchover
docker exec patroni1 patronictl switchover postgres-ha --candidate patroni2 --force
```

### View Logs

```bash
# Patroni logs
docker logs -f patroni1

# etcd logs
docker logs -f etcd1

# HAProxy logs
docker logs -f haproxy
```

### Backup

```bash
# Manual backup
docker exec patroni1 pg_dump -U postgres -d postgres > backup.sql
```

### Restart Node

```bash
# Restart everything on VM1
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml restart

# Restart only Patroni
docker restart patroni1
```

---

## Troubleshooting

### etcd Cluster Not Forming

```bash
# Check logs
docker logs etcd1

# Verify connectivity
docker exec etcd1 nc -zv <NODE2_IP> 2380

# If corrupted, clean and restart
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml down -v
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d
```

### Patroni Not Electing Leader

```bash
# Check etcd is healthy first
docker exec etcd1 etcdctl endpoint health --cluster

# Check Patroni logs
docker logs patroni1
```

### HAProxy Shows Backends DOWN

```bash
# Test Patroni API directly
curl http://<NODE1_IP>:8008/health
curl http://<NODE1_IP>:8008/primary

# Check HAProxy logs
docker logs haproxy
```

---

## Port Reference

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| etcd client | 2379 | TCP | Client connections |
| etcd peer | 2380 | TCP | Cluster communication |
| PostgreSQL | 5432 | TCP | Database connections |
| Patroni API | 8008 | TCP | REST API / health checks |
| HAProxy primary | 5000 | TCP | R/W connections |
| HAProxy replica | 5001 | TCP | R/O connections |
| HAProxy stats | 7000 | HTTP | Dashboard |

---

## File Structure

```
.
├── docker-compose.vm1.yml      # VM1: etcd1 + patroni1
├── docker-compose.vm2.yml      # VM2: etcd2 + patroni2
├── docker-compose.vm3.yml      # VM3: etcd3 + patroni3
├── docker-compose.haproxy.yml  # HAProxy load balancer
├── docker-compose.dev.yml      # Single-host development setup
├── .env.vm1                    # VM1 configuration
├── .env.vm2                    # VM2 configuration
├── .env.vm3                    # VM3 configuration
├── .env.haproxy                # HAProxy configuration
├── .env.dev                    # Development configuration
├── haproxy/
│   ├── haproxy.cfg             # Multi-VM HAProxy config
│   └── haproxy.dev.cfg         # Single-host HAProxy config
├── scripts/
│   ├── start-cluster.sh        # Start cluster helper
│   ├── stop-cluster.sh         # Stop cluster helper
│   └── cluster-status.sh       # Status check helper
└── HA-SETUP.md                 # Detailed documentation
```

---

## Additional Resources

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Zalando Spilo](https://github.com/zalando/spilo)
- [etcd Documentation](https://etcd.io/docs/)
- [HAProxy Documentation](http://www.haproxy.org/)
