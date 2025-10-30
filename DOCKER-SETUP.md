# Docker-Only Setup Guide

This guide explains how to deploy the PostgreSQL HA cluster entirely with Docker (no Kubernetes required).

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Docker Network                        │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   VM1/Node1  │    │   VM2/Node2  │    │   VM3/Node3  │  │
│  │              │    │              │    │              │  │
│  │ Consul       │◄───┤ Consul       │◄───┤ Consul       │  │
│  │ Server       │───►│ Server       │───►│ Server       │  │
│  │ (Leader)     │    │ (Follower)   │    │ (Follower)   │  │
│  │              │    │              │    │              │  │
│  │ Patroni      │    │ Patroni      │    │ Patroni      │  │
│  │ PostgreSQL   │◄──►│ PostgreSQL   │◄──►│ PostgreSQL   │  │
│  │ (Primary)    │    │ (Replica)    │    │ (Replica)    │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                    │                    │         │
└─────────┼────────────────────┼────────────────────┼─────────┘
          │                    │                    │
     ┌────▼────────────────────▼────────────────────▼────┐
     │              HAProxy (Optional)                    │
     │         Master: 5000 | Replicas: 5001             │
     └───────────────────────────────────────────────────┘
```

## Key Components

### Consul Servers (3 nodes)
- **Purpose**: Distributed configuration store (DCS) for Patroni
- **Mode**: Server mode (not agent mode)
- **Consensus**: Raft algorithm requires 2 out of 3 nodes for quorum
- **Ports**: 8500 (HTTP), 8300-8302 (Raft/Serf), 8600 (DNS)

### Patroni + PostgreSQL (3 nodes)
- **Purpose**: High-availability PostgreSQL cluster
- **Primary**: One elected primary (read/write)
- **Replicas**: Two streaming replicas (read-only)
- **Auto-failover**: Patroni detects failures and promotes replicas

### HAProxy (Optional)
- **Purpose**: Single endpoint for applications
- **Master endpoint**: Port 5000 (routes to current primary)
- **Replica endpoint**: Port 5001 (round-robin to replicas)
- **Stats**: Port 7000

## Quick Start

### 1. Configure Consul Server Addresses

Edit the three docker-compose files to set the `retry-join` addresses.

**For single host (localhost):**

Use `host.docker.internal` (Windows/WSL) or your machine's IP address (Linux/macOS).

In `docker-compose.vm1.yml`, change:
```yaml
-retry-join=<VM2_IP>:8301
-retry-join=<VM3_IP>:8301
```

To (Windows/WSL):
```yaml
-retry-join=host.docker.internal:8304
-retry-join=host.docker.internal:8307
```

Or (Linux/macOS with IP 192.168.1.100):
```yaml
-retry-join=192.168.1.100:8304
-retry-join=192.168.1.100:8307
```

**Repeat for vm2 and vm3** (they point to different port numbers):
- VM1 uses ports: 8301 (its own Serf LAN port)
- VM2 uses ports: 8304 (its Serf LAN port on host)
- VM3 uses ports: 8307 (its Serf LAN port on host)

### 2. Set Environment Variables

```bash
# Windows/WSL
export HOST_ADDR=host.docker.internal

# Linux/macOS (find your IP)
export HOST_ADDR=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# Patroni addresses
export CONNECT_ADDRESS_VM1="$HOST_ADDR:5432"
export CONNECT_ADDRESS_VM2="$HOST_ADDR:5433"
export CONNECT_ADDRESS_VM3="$HOST_ADDR:5434"
export RESTAPI_CONNECT_ADDRESS_VM1="$HOST_ADDR:8008"
export RESTAPI_CONNECT_ADDRESS_VM2="$HOST_ADDR:8009"
export RESTAPI_CONNECT_ADDRESS_VM3="$HOST_ADDR:8010"

# Passwords
export POSTGRES_PASSWORD=your-secure-password
export REPLICATION_PASSWORD=your-replication-password
```

### 3. Build Patroni Image

```bash
docker build -f docker/Dockerfile.patroni -t patroni-postgres .
```

### 4. Start All Nodes

**IMPORTANT**: Start all three within 60 seconds so Consul can form quorum.

```bash
docker-compose -f docker-compose.vm1.yml up -d
docker-compose -f docker-compose.vm2.yml up -d
docker-compose -f docker-compose.vm3.yml up -d
```

### 5. Verify Consul Cluster

Wait 30-60 seconds, then check:

```bash
# Should show 3 servers, all "alive"
docker exec consul-server-vm1 consul members

# Should show leader elected
docker exec consul-server-vm1 consul operator raft list-peers

# Open Consul UI
# Open browser to http://localhost:8500
```

### 6. Verify Patroni Cluster

```bash
# Should show 1 Leader, 2 Replicas
docker exec patroni-postgres-vm1 patronictl list
```

Expected output:
```
+ Cluster: patroni (7234567890123456789) -----+----+-----------+
| Member              | Host           | Role    | State   | TL | Lag in MB |
+---------------------+----------------+---------+---------+----+-----------+
| patroni-postgres-vm1| 192.168.1.1:5432| Leader  | running |  1 |           |
| patroni-postgres-vm2| 192.168.1.1:5433| Replica | running |  1 |         0 |
| patroni-postgres-vm3| 192.168.1.1:5434| Replica | running |  1 |         0 |
+---------------------+----------------+---------+---------+----+-----------+
```

### 7. Test PostgreSQL Connection

```bash
# Connect to primary
psql -h localhost -p 5432 -U postgres -c "SELECT version();"

# Test replication
psql -h localhost -p 5433 -U postgres -c "SELECT pg_is_in_recovery();"  # Should return 't' (true)
```

## Multi-VM Deployment

For deploying across multiple VMs (production setup):

### 1. Update Consul Retry-Join Addresses

In `docker-compose.vm1.yml`:
```yaml
-retry-join=192.168.1.102:8301  # VM2's IP
-retry-join=192.168.1.103:8301  # VM3's IP
```

In `docker-compose.vm2.yml`:
```yaml
-retry-join=192.168.1.101:8301  # VM1's IP
-retry-join=192.168.1.103:8301  # VM3's IP
```

In `docker-compose.vm3.yml`:
```yaml
-retry-join=192.168.1.101:8301  # VM1's IP
-retry-join=192.168.1.102:8301  # VM2's IP
```

### 2. Configure Firewall Rules

Open these ports between VMs:
- **8300-8302**: Consul RPC and Serf (TCP + UDP)
- **8500**: Consul HTTP API (TCP)
- **8600**: Consul DNS (TCP + UDP)
- **5432**: PostgreSQL (TCP)
- **8008**: Patroni REST API (TCP)

### 3. Set Environment Variables Per VM

On VM1:
```bash
export CONNECT_ADDRESS_VM1="192.168.1.101:5432"
export RESTAPI_CONNECT_ADDRESS_VM1="192.168.1.101:8008"
```

On VM2:
```bash
export CONNECT_ADDRESS_VM2="192.168.1.102:5432"
export RESTAPI_CONNECT_ADDRESS_VM2="192.168.1.102:8008"
```

On VM3:
```bash
export CONNECT_ADDRESS_VM3="192.168.1.103:5432"
export RESTAPI_CONNECT_ADDRESS_VM3="192.168.1.103:8008"
```

### 4. Deploy

On each VM:
```bash
# VM1
docker-compose -f docker-compose.vm1.yml up -d

# VM2
docker-compose -f docker-compose.vm2.yml up -d

# VM3
docker-compose -f docker-compose.vm3.yml up -d
```

## Troubleshooting

### Consul Not Forming Cluster

**Symptom**: `consul members` shows only 1 server

**Causes**:
1. Retry-join addresses are incorrect
2. Firewall blocking ports 8300-8302
3. Nodes started too far apart (>5 minutes)

**Fix**:
```bash
# Check logs
docker logs consul-server-vm1 | grep -i "retry-join"

# Verify port connectivity
docker exec consul-server-vm1 nc -zv <other-vm-ip> 8301

# Restart all nodes together
docker-compose -f docker-compose.vm1.yml restart
docker-compose -f docker-compose.vm2.yml restart
docker-compose -f docker-compose.vm3.yml restart
```

### Patroni Cannot Reach Consul

**Symptom**: Patroni logs show "DCS is not accessible"

**Causes**:
1. Consul not healthy yet
2. Wrong CONSUL_HOST in environment

**Fix**:
```bash
# Check Consul health
docker exec consul-server-vm1 consul members

# Test connectivity from Patroni
docker exec patroni-postgres-vm1 curl http://consul-server:8500/v1/status/leader

# Check Patroni logs
docker logs patroni-postgres-vm1 | tail -50
```

### No Patroni Leader Elected

**Symptom**: `patronictl list` shows no Leader or fails

**Causes**:
1. Consul cluster doesn't have quorum
2. CONNECT_ADDRESS variables not set correctly
3. Nodes cannot reach each other

**Fix**:
```bash
# Verify Consul quorum
docker exec consul-server-vm1 consul operator raft list-peers

# Check Patroni can register
docker exec consul-server-vm1 consul catalog services

# Verify reachability
docker exec patroni-postgres-vm1 curl http://$CONNECT_ADDRESS_VM2:8009/health
```

### Network Issues

**Symptom**: Nodes cannot communicate

**Fix**:
```bash
# Check all containers are running
docker ps | grep -E "consul-server|patroni-postgres"

# Test DNS resolution
docker exec patroni-postgres-vm1 nslookup consul-server

# Test port connectivity
docker exec patroni-postgres-vm1 nc -zv consul-server 8500
```

## Operations

### View Logs

```bash
# All logs for VM1
docker-compose -f docker-compose.vm1.yml logs -f

# Only Consul logs
docker logs -f consul-server-vm1

# Only Patroni logs
docker logs -f patroni-postgres-vm1
```

### Manual Failover

```bash
# Trigger failover to specific replica
docker exec patroni-postgres-vm1 patronictl failover --candidate patroni-postgres-vm2

# Interactive failover
docker exec -it patroni-postgres-vm1 patronictl failover
```

### Restart a Node

```bash
# Restart entire VM1 stack
docker-compose -f docker-compose.vm1.yml restart

# Restart only Patroni
docker-compose -f docker-compose.vm1.yml restart patroni-postgres

# Restart only Consul
docker-compose -f docker-compose.vm1.yml restart consul-server
```

### Scale Down/Up

```bash
# Stop one node (cluster remains operational with 2/3)
docker-compose -f docker-compose.vm3.yml down

# Start it again
docker-compose -f docker-compose.vm3.yml up -d
```

### Backup

```bash
# Manual backup using pg_dump
docker exec patroni-postgres-vm1 pg_dump -U postgres postgres > backup.sql

# List backups (if WAL archiving configured)
docker exec patroni-postgres-vm1 patronictl list-backups
```

## Advantages Over Kubernetes Setup

1. **Simpler**: No need to manage Kubernetes cluster
2. **Lower overhead**: Fewer moving parts and processes
3. **Easier debugging**: Direct access to containers and logs
4. **VM-friendly**: Perfect for traditional VM deployments
5. **Cost-effective**: No K8s control plane resource usage

## When to Use Kubernetes Instead

- You already have K8s infrastructure
- Need K8s-native features (Service Mesh, Operators)
- Want to deploy Supabase on same cluster
- Require advanced pod scheduling/affinity
- Need automated rolling updates and canary deployments

## Additional Resources

- [Consul Docker Documentation](https://hub.docker.com/_/consul)
- [Patroni Documentation](https://patroni.readthedocs.io/)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- [HAProxy Documentation](http://www.haproxy.org/)

## License

MIT

