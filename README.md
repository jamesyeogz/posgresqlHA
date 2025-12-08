# PostgreSQL High Availability with Patroni, etcd, and HAProxy

A production-ready PostgreSQL High Availability cluster using:
- **Patroni** (via Zalando Spilo) for PostgreSQL HA management and automatic failover
- **etcd** as the Distributed Configuration Store (DCS) for cluster coordination
- **HAProxy** for load balancing and automatic primary/replica routing
- **Docker** and **Docker Compose** for easy deployment

All components use **existing Docker images** - no custom builds required.

## Features

- ✅ **3-node PostgreSQL 16 cluster** with automatic failover
- ✅ **3-node etcd cluster** for distributed consensus
- ✅ **Streaming replication** between primary and replicas
- ✅ **Automatic leader election** on primary failure
- ✅ **HAProxy load balancing** with separate read/write endpoints
- ✅ **Single-host development** or **multi-VM production** deployment options
- ✅ **No custom image builds** - uses official Zalando Spilo, etcd, and HAProxy images
- ✅ **No Kubernetes required** - pure Docker solution

## Architecture

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

## Docker Images Used

| Component | Image | Version |
|-----------|-------|---------|
| etcd | `quay.io/coreos/etcd` | v3.5.11 |
| Patroni/PostgreSQL | `ghcr.io/zalando/spilo-16` | 3.2-p2 |
| HAProxy | `haproxy` | 2.9-alpine |

**No custom images need to be built** - everything is pulled from public registries.

## Prerequisites

- Docker (20.10+) and Docker Compose (v2+)
- At least 4GB RAM available for Docker
- Network ports available: 2379-2380, 5432, 5000-5001, 7000, 8008

## Quick Start

### Option 1: Single-Host Development (Fastest)

Run the entire cluster on one machine:

```bash
# Start everything
docker-compose -f docker-compose.dev.yml up -d

# Check cluster status (wait ~60 seconds for initialization)
docker exec patroni1 patronictl list

# Connect to database
psql -h localhost -p 5000 -U postgres -d postgres
# Password: postgres (default)
```

**Connection Endpoints:**

| Endpoint | Port | Purpose |
|----------|------|---------|
| Primary (R/W) | `localhost:5000` | Write operations (via HAProxy) |
| Replica (R/O) | `localhost:5001` | Read operations (via HAProxy) |
| HAProxy Stats | `localhost:7000/stats` | Dashboard (admin/admin123) |

**Stop the cluster:**
```bash
docker-compose -f docker-compose.dev.yml down       # Keep data
docker-compose -f docker-compose.dev.yml down -v    # Remove all data
```

### Option 2: Multi-VM Production

Deploy across 3 separate VMs for production high availability.

**See [HA-SETUP.md](HA-SETUP.md) for detailed instructions.**

Quick overview:

1. **Edit environment files** on each VM:
   ```bash
   # On VM1
   vim .env.vm1
   # Update NODE1_IP, NODE2_IP, NODE3_IP with actual IPs
   # Set POSTGRES_PASSWORD and REPLICATION_PASSWORD
   ```

2. **Update HAProxy config**:
   ```bash
   vim haproxy/haproxy.cfg
   # Replace placeholder IPs with actual VM IPs
   ```

3. **Start cluster** (all nodes within 60 seconds):
   ```bash
   # VM1
   docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d
   
   # VM2
   docker-compose --env-file .env.vm2 -f docker-compose.vm2.yml up -d
   
   # VM3
   docker-compose --env-file .env.vm3 -f docker-compose.vm3.yml up -d
   ```

4. **Start HAProxy** (on any VM):
   ```bash
   docker-compose --env-file .env.haproxy -f docker-compose.haproxy.yml up -d
   ```

## File Structure

```
.
├── docker-compose.dev.yml      # Single-host development setup (all-in-one)
├── docker-compose.vm1.yml      # VM1: etcd1 + patroni1
├── docker-compose.vm2.yml      # VM2: etcd2 + patroni2
├── docker-compose.vm3.yml      # VM3: etcd3 + patroni3
├── docker-compose.haproxy.yml  # HAProxy load balancer
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
├── HA-SETUP.md                 # Detailed HA setup documentation
└── DOCKER-SETUP.md             # Quick reference guide
```

## Common Operations

### Check Cluster Status

```bash
# Patroni cluster status
docker exec patroni1 patronictl list

# etcd cluster health
docker exec etcd1 etcdctl endpoint health --cluster

# etcd member list
docker exec etcd1 etcdctl member list -w table
```

### Manual Failover

```bash
# Failover to specific node
docker exec patroni1 patronictl failover postgres-ha --candidate patroni2 --force

# Graceful switchover
docker exec patroni1 patronictl switchover postgres-ha --candidate patroni2 --force
```

### View Logs

```bash
docker logs -f patroni1    # Patroni logs
docker logs -f etcd1       # etcd logs
docker logs -f haproxy     # HAProxy logs
```

### Backup

```bash
# SQL dump
docker exec patroni1 pg_dump -U postgres -d postgres > backup.sql
```

## Helper Scripts

```bash
# Start a specific node
./scripts/start-cluster.sh 1                    # Start VM1
./scripts/start-cluster.sh 1 --with-haproxy     # Start VM1 + HAProxy

# Stop a specific node
./scripts/stop-cluster.sh 1                     # Stop VM1
./scripts/stop-cluster.sh --all                 # Stop all nodes
./scripts/stop-cluster.sh 1 --remove-volumes    # Stop and remove data

# Check cluster status
./scripts/cluster-status.sh                     # One-time check
./scripts/cluster-status.sh --watch             # Continuous monitoring
```

## Testing Failover

```bash
# 1. Check current leader
docker exec patroni1 patronictl list

# 2. Stop the leader
docker stop patroni1

# 3. Wait 30-60 seconds and verify new leader elected
docker exec patroni2 patronictl list

# 4. Restart original node (becomes replica)
docker start patroni1

# 5. Verify cluster recovered
docker exec patroni1 patronictl list
```

## Port Reference

| Port | Service | Description |
|------|---------|-------------|
| 2379 | etcd | Client connections |
| 2380 | etcd | Peer communication |
| 5432 | PostgreSQL | Database connections |
| 8008 | Patroni | REST API / health checks |
| 5000 | HAProxy | Primary (R/W) endpoint |
| 5001 | HAProxy | Replica (R/O) endpoint |
| 7000 | HAProxy | Stats dashboard |

## Environment Variables

### Required (Production)

```bash
NODE1_IP=192.168.1.101
NODE2_IP=192.168.1.102
NODE3_IP=192.168.1.103
POSTGRES_PASSWORD=secure-password
REPLICATION_PASSWORD=secure-password
```

### Optional

```bash
ETCD_CLIENT_PORT=2379
ETCD_PEER_PORT=2380
POSTGRES_PORT=5432
PATRONI_API_PORT=8008
```

## Security Considerations

- ⚠️ Change default passwords before production use
- ⚠️ Update HAProxy stats credentials (default: admin/admin123)
- Consider enabling SSL/TLS for PostgreSQL connections
- Configure firewall rules to restrict access
- Use private network for cluster communication

## Troubleshooting

See [HA-SETUP.md](HA-SETUP.md#troubleshooting) for detailed troubleshooting guide.

**Quick checks:**

```bash
# etcd not forming cluster?
docker logs etcd1
docker exec etcd1 etcdctl endpoint health --cluster

# Patroni not electing leader?
docker logs patroni1
docker exec patroni1 patronictl list

# HAProxy showing backends DOWN?
curl http://<NODE_IP>:8008/health
docker logs haproxy
```

## Documentation

- [HA-SETUP.md](HA-SETUP.md) - Complete setup guide with detailed instructions
- [DOCKER-SETUP.md](DOCKER-SETUP.md) - Quick reference guide

## External Resources

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Zalando Spilo](https://github.com/zalando/spilo)
- [etcd Documentation](https://etcd.io/docs/)
- [HAProxy Documentation](http://www.haproxy.org/)

## License

MIT License
