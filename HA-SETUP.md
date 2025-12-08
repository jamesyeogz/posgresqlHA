# PostgreSQL High Availability Setup with Patroni, etcd, and HAProxy

This guide provides a complete setup for a highly available PostgreSQL cluster using:
- **Patroni** (via Zalando Spilo image) - PostgreSQL HA management
- **etcd** - Distributed configuration store (DCS)
- **HAProxy** - Load balancing and automatic failover routing

## Architecture Overview

```
                                    ┌─────────────────┐
                                    │    HAProxy      │
                                    │  (Load Balancer)│
                                    │                 │
                                    │ Port 5000: R/W  │
                                    │ Port 5001: R/O  │
                                    │ Port 7000: Stats│
                                    └────────┬────────┘
                                             │
              ┌──────────────────────────────┼──────────────────────────────┐
              │                              │                              │
              ▼                              ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────┐    ┌─────────────────────────┐
│         VM1             │    │         VM2             │    │         VM3             │
│                         │    │                         │    │                         │
│  ┌───────────────────┐  │    │  ┌───────────────────┐  │    │  ┌───────────────────┐  │
│  │      etcd1        │  │    │  │      etcd2        │  │    │  │      etcd3        │  │
│  │    (2379/2380)    │◄─┼────┼──┤    (2379/2380)    │◄─┼────┼──┤    (2379/2380)    │  │
│  └───────────────────┘  │    │  └───────────────────┘  │    │  └───────────────────┘  │
│           │             │    │           │             │    │           │             │
│           ▼             │    │           ▼             │    │           ▼             │
│  ┌───────────────────┐  │    │  ┌───────────────────┐  │    │  ┌───────────────────┐  │
│  │    Patroni1       │  │    │  │    Patroni2       │  │    │  │    Patroni3       │  │
│  │   PostgreSQL 16   │  │    │  │   PostgreSQL 16   │  │    │  │   PostgreSQL 16   │  │
│  │   (5432/8008)     │  │    │  │   (5432/8008)     │  │    │  │   (5432/8008)     │  │
│  │                   │  │    │  │                   │  │    │  │                   │  │
│  │  Leader/Replica   │◄─┼────┼──┤     Replica       │◄─┼────┼──┤     Replica       │  │
│  └───────────────────┘  │    │  └───────────────────┘  │    │  └───────────────────┘  │
│                         │    │                         │    │                         │
└─────────────────────────┘    └─────────────────────────┘    └─────────────────────────┘
```

## Components

| Component | Image | Version | Purpose |
|-----------|-------|---------|---------|
| etcd | `quay.io/coreos/etcd` | v3.5.11 | Distributed configuration store |
| Patroni/PostgreSQL | `ghcr.io/zalando/spilo-16` | 3.2-p2 | PostgreSQL 16 with Patroni HA |
| HAProxy | `haproxy` | 2.9-alpine | Load balancer |

## Prerequisites

- 3 VMs (or servers) with Docker and Docker Compose installed
- Network connectivity between all nodes
- Open firewall ports (see Network Requirements)

### Minimum System Requirements (per node)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Storage | 20 GB SSD | 100 GB SSD |

### Network Requirements

Open these ports between all nodes:

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 2379 | TCP | etcd | Client connections |
| 2380 | TCP | etcd | Peer communication |
| 5432 | TCP | PostgreSQL | Database connections |
| 8008 | TCP | Patroni | REST API (health checks) |

HAProxy (if on separate host):

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 5000 | TCP | HAProxy | Primary (R/W) endpoint |
| 5001 | TCP | HAProxy | Replica (R/O) endpoint |
| 7000 | TCP | HAProxy | Stats dashboard |

## Quick Start

### Step 1: Prepare Environment Files

On **each VM**, copy and edit the environment file:

**VM1:**
```bash
# Edit .env.vm1 with your actual IPs and passwords
vim .env.vm1
```

**VM2:**
```bash
# Edit .env.vm2 with your actual IPs and passwords
vim .env.vm2
```

**VM3:**
```bash
# Edit .env.vm3 with your actual IPs and passwords
vim .env.vm3
```

**CRITICAL:** Update these values in ALL .env files:
```bash
# Replace with your actual VM IPs
NODE1_IP=<VM1_IP_ADDRESS>
NODE2_IP=<VM2_IP_ADDRESS>
NODE3_IP=<VM3_IP_ADDRESS>

# Set secure passwords (must be same on all nodes!)
POSTGRES_PASSWORD=<strong-password>
REPLICATION_PASSWORD=<strong-password>
```

### Step 2: Update HAProxy Configuration

Edit `haproxy/haproxy.cfg` and update the server IPs:
```bash
vim haproxy/haproxy.cfg
```

Replace `192.168.1.101`, `192.168.1.102`, `192.168.1.103` with your actual VM IPs.

### Step 3: Start the Cluster

**IMPORTANT:** Start all nodes within 60 seconds for etcd cluster formation.

**On VM1:**
```bash
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d
```

**On VM2:**
```bash
docker-compose --env-file .env.vm2 -f docker-compose.vm2.yml up -d
```

**On VM3:**
```bash
docker-compose --env-file .env.vm3 -f docker-compose.vm3.yml up -d
```

### Step 4: Verify etcd Cluster

Wait 30 seconds, then check etcd cluster health:

```bash
# On any node
docker exec etcd1 etcdctl endpoint health --cluster

# Expected output:
# http://<IP>:2379 is healthy: successfully committed proposal
# http://<IP>:2379 is healthy: successfully committed proposal
# http://<IP>:2379 is healthy: successfully committed proposal
```

### Step 5: Verify Patroni Cluster

```bash
# On any node
docker exec patroni1 patronictl list

# Expected output:
# + Cluster: postgres-ha -----------+---------+---------+----+-----------+
# | Member    | Host           | Role    | State   | TL | Lag in MB |
# +-----------+----------------+---------+---------+----+-----------+
# | patroni1  | 192.168.1.101  | Leader  | running |  1 |           |
# | patroni2  | 192.168.1.102  | Replica | running |  1 |         0 |
# | patroni3  | 192.168.1.103  | Replica | running |  1 |         0 |
# +-----------+----------------+---------+---------+----+-----------+
```

### Step 6: Start HAProxy (Optional but Recommended)

HAProxy can run on any node or a dedicated server:

```bash
# Edit the HAProxy env file
vim .env.haproxy

# Start HAProxy
docker-compose --env-file .env.haproxy -f docker-compose.haproxy.yml up -d
```

### Step 7: Test Database Connection

```bash
# Connect to primary (read/write) via HAProxy
psql -h <HAPROXY_IP> -p 5000 -U postgres -d postgres

# Connect to replica (read-only) via HAProxy
psql -h <HAPROXY_IP> -p 5001 -U postgres -d postgres

# Direct connection to a specific node
psql -h <VM1_IP> -p 5432 -U postgres -d postgres
```

## File Structure

```
.
├── docker-compose.vm1.yml      # VM1 compose (etcd1 + patroni1)
├── docker-compose.vm2.yml      # VM2 compose (etcd2 + patroni2)
├── docker-compose.vm3.yml      # VM3 compose (etcd3 + patroni3)
├── docker-compose.haproxy.yml  # HAProxy compose
├── .env.vm1                    # VM1 environment variables
├── .env.vm2                    # VM2 environment variables
├── .env.vm3                    # VM3 environment variables
├── .env.haproxy                # HAProxy environment variables
├── haproxy/
│   └── haproxy.cfg             # HAProxy configuration
└── scripts/
    ├── start-cluster.sh        # Start all services
    ├── stop-cluster.sh         # Stop all services
    └── cluster-status.sh       # Check cluster status
```

## Connection Endpoints

| Endpoint | Port | Purpose | Usage |
|----------|------|---------|-------|
| HAProxy Primary | 5000 | Read/Write | Application writes |
| HAProxy Replica | 5001 | Read-Only | Read scaling |
| HAProxy Any | 5002 | Any healthy node | General queries |
| HAProxy Stats | 7000 | Dashboard | Monitoring |
| Direct PostgreSQL | 5432 | Direct node access | Admin/debugging |
| Patroni API | 8008 | REST API | Monitoring/management |

## HAProxy Stats Dashboard

Access the HAProxy stats dashboard at:
```
http://<HAPROXY_IP>:7000/stats
```

Default credentials:
- Username: `admin`
- Password: `admin123`

## Operations Guide

### Check Cluster Status

```bash
# Patroni cluster status
docker exec patroni1 patronictl list

# etcd cluster status
docker exec etcd1 etcdctl endpoint status --cluster -w table

# etcd member list
docker exec etcd1 etcdctl member list -w table
```

### Manual Failover

```bash
# Failover to a specific node
docker exec patroni1 patronictl failover postgres-ha --candidate patroni2 --force

# Switchover (graceful, no data loss)
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

### Restart a Node

```bash
# On VM1
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml restart

# Restart only Patroni
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml restart patroni1

# Restart only etcd
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml restart etcd1
```

### Stop/Start Cluster

```bash
# Stop (on each VM)
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml down

# Start (on each VM)
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d
```

### Scale Down/Up

```bash
# Stop one node (cluster remains operational with 2/3 nodes)
docker-compose --env-file .env.vm3 -f docker-compose.vm3.yml down

# Start it again
docker-compose --env-file .env.vm3 -f docker-compose.vm3.yml up -d
```

### Backup

```bash
# Manual backup using pg_dump
docker exec patroni1 pg_dump -U postgres -d postgres > backup.sql

# Continuous archiving is handled by Patroni/Spilo
```

### Reinitialize a Failed Node

```bash
# If a replica gets out of sync
docker exec patroni2 patronictl reinit postgres-ha patroni2 --force
```

## Troubleshooting

### etcd Not Forming Cluster

**Symptoms:** `etcdctl endpoint health` shows unhealthy or timeout

**Common causes:**
1. IP addresses incorrect in .env files
2. Firewall blocking ports 2379/2380
3. Nodes not started within 60 seconds

**Solutions:**
```bash
# Check etcd logs
docker logs etcd1

# Verify connectivity
docker exec etcd1 nc -zv <NODE2_IP> 2380

# If cluster is corrupted, clean and restart
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml down -v
docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d
```

### Patroni Not Electing Leader

**Symptoms:** `patronictl list` shows no Leader or fails

**Common causes:**
1. etcd cluster not healthy
2. CONNECT_ADDRESS environment variables incorrect
3. Nodes can't reach each other

**Solutions:**
```bash
# Check etcd is healthy first
docker exec etcd1 etcdctl endpoint health --cluster

# Check Patroni logs
docker logs patroni1

# Verify Patroni can reach etcd
docker exec patroni1 curl http://<NODE1_IP>:2379/health
```

### HAProxy Shows All Backends Down

**Symptoms:** Stats page shows all servers in "DOWN" state

**Common causes:**
1. Wrong IP addresses in haproxy.cfg
2. Patroni API port (8008) not accessible
3. Firewall blocking connections

**Solutions:**
```bash
# Test Patroni API directly
curl http://<NODE1_IP>:8008/health
curl http://<NODE1_IP>:8008/primary
curl http://<NODE1_IP>:8008/replica

# Check HAProxy logs
docker logs haproxy

# Verify network connectivity
docker exec haproxy nc -zv <NODE1_IP> 8008
```

### Connection Refused on Port 5432

**Symptoms:** Can't connect to PostgreSQL

**Common causes:**
1. PostgreSQL not ready yet
2. pg_hba.conf not allowing connections
3. Wrong password

**Solutions:**
```bash
# Check if PostgreSQL is accepting connections
docker exec patroni1 pg_isready -h localhost -p 5432

# Check Patroni status
docker exec patroni1 patronictl list

# View PostgreSQL logs
docker exec patroni1 cat /home/postgres/pgdata/pgroot/pg_log/postgresql-*.log
```

### Replication Lag

**Symptoms:** `patronictl list` shows high "Lag in MB"

**Common causes:**
1. Network latency between nodes
2. Slow disk I/O on replica
3. Heavy write load

**Solutions:**
```bash
# Check replication status
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check replication slots
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_replication_slots;"
```

## Security Considerations

### Production Hardening Checklist

- [ ] Change default passwords in all .env files
- [ ] Update HAProxy stats credentials
- [ ] Enable SSL/TLS for PostgreSQL connections
- [ ] Enable SSL/TLS for etcd communication
- [ ] Configure firewall rules
- [ ] Use private network for cluster communication
- [ ] Enable PostgreSQL connection logging
- [ ] Set up monitoring and alerting

### Enable PostgreSQL SSL

Add to your docker-compose environment:
```yaml
environment:
  - PATRONI_POSTGRESQL_PARAMETERS_SSL=on
  - PATRONI_POSTGRESQL_PARAMETERS_SSL_CERT_FILE=/path/to/server.crt
  - PATRONI_POSTGRESQL_PARAMETERS_SSL_KEY_FILE=/path/to/server.key
```

## Single-Host Development Setup

For testing on a single machine, use different ports:

**docker-compose.dev.yml:**
```yaml
# See docker-compose.dev.yml for single-host setup
# Uses ports: 
# - etcd: 2379, 2380, 2381 (client) and 2382, 2383, 2384 (peer)
# - PostgreSQL: 5432, 5433, 5434
# - Patroni API: 8008, 8009, 8010
```

## Additional Resources

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Zalando Spilo](https://github.com/zalando/spilo)
- [etcd Documentation](https://etcd.io/docs/)
- [HAProxy Documentation](http://www.haproxy.org/)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)

## Support

For issues with:
- **Patroni/Spilo**: https://github.com/zalando/spilo/issues
- **etcd**: https://github.com/etcd-io/etcd/issues
- **HAProxy**: https://github.com/haproxy/haproxy/issues
