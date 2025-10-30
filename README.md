# PostgreSQL HA with Patroni, Consul, and HAProxy (Supabase-ready)

A production-ready PostgreSQL High Availability cluster using:
- **Patroni** for PostgreSQL HA management and automatic failover
- **Consul** as the Distributed Configuration Store (DCS) for cluster coordination
- **HAProxy** (optional) for load balancing
- **Docker** and **Docker Compose** for easy deployment

All components run in Docker, making it simple to deploy on a single host for testing or across multiple VMs for production.

## Features

- ✅ **3-node PostgreSQL cluster** with automatic failover
- ✅ **3-node Consul server cluster** for distributed consensus
- ✅ **Streaming replication** between primary and replicas
- ✅ **Automatic leader election** on primary failure
- ✅ **Supabase schema** auto-initialization on bootstrap
- ✅ **Single-host demo** or **multi-VM deployment** options
- ✅ **No Kubernetes required** - pure Docker solution

## Architecture

```
Docker Host / VMs
  ├─ Consul Server 1 (vm1)               : 8500 HTTP/UI, 8301 Serf, 8600 DNS
  ├─ Consul Server 2 (vm2)               : 8501 HTTP/UI, 8304 Serf, 8601 DNS  
  ├─ Consul Server 3 (vm3)               : 8502 HTTP/UI, 8307 Serf, 8602 DNS
  ├─ Patroni PostgreSQL 1 (vm1)          : 5432 (PG), 8008 (API)
  ├─ Patroni PostgreSQL 2 (vm2)          : 5433 (PG), 8009 (API)
  ├─ Patroni PostgreSQL 3 (vm3)          : 5434 (PG), 8010 (API)
  └─ HAProxy (optional)                   : 5000 (primary), 5001 (replicas), 7000 (stats)

Networking:
  - Local Dev: Shared Docker Network (patroni-shared-bridge) for inter-container communication
  - Production: Each VM has isolated Docker network, communicate via VM IPs on L3 network
```

## Prerequisites

**Required:**
- Docker (20.10+) and Docker Compose (v2+)
- At least 4GB RAM available for Docker
- Ports available: 5432-5434, 8008-8010, 8500-8502

**Optional:**
- On Windows: PowerShell (for batch scripts) or WSL2
- For multi-VM: Network connectivity between VMs

## Quick Start (Single Host)

This is the fastest way to get a working 3-node HA cluster on one machine:

> **⚠️ Important**: The shared Docker network approach below is **for local development/testing only**. In production multi-VM deployments, each VM has its own isolated Docker network and containers communicate via VM IP addresses (see [Multi-VM Deployment](#multi-vm-deployment-production) section).

### 1. Create the shared Docker network (Local Development Only)

```bash
docker network create patroni-shared-bridge
```

This network allows all containers on the same host to communicate using container names (e.g., `consul-server-vm2`) instead of IP addresses.

### 2. Configure environment variables

Copy the example environment file:

```bash
cp env.local.example env.local
```

Edit `env.local` and set your passwords:

```bash
# Required - PostgreSQL passwords
POSTGRES_PASSWORD=your_secure_postgres_password
REPLICATION_PASSWORD=your_secure_replication_password

# Optional - Consul ACL (leave empty for dev)
CONSUL_ACL_TOKEN=

# Network addressing for single-host setup
CONNECT_ADDRESS_VM1=host.docker.internal:5432
CONNECT_ADDRESS_VM2=host.docker.internal:5433
CONNECT_ADDRESS_VM3=host.docker.internal:5434
RESTAPI_CONNECT_ADDRESS_VM1=host.docker.internal:8008
RESTAPI_CONNECT_ADDRESS_VM2=host.docker.internal:8009
RESTAPI_CONNECT_ADDRESS_VM3=host.docker.internal:8010
```

**Note for Linux/macOS:** Replace `host.docker.internal` with your actual host IP address (e.g., `192.168.1.100`).

### 3. Build the Patroni image

```bash
docker build -f docker/Dockerfile.patroni -t patroni-postgres .
```

This builds a custom Patroni image that:
- Runs with root permissions and uses `gosu` to switch to postgres user
- Automatically fixes data directory permissions
- Waits for Consul to be available before starting
- Processes Patroni config with environment variable substitution

### 4. Start the cluster

**Windows:**
```batch
.\start-cluster.bat
```

**Linux/macOS:**
```bash
chmod +x start-cluster.sh
./start-cluster.sh
```

Or manually:
```bash
docker-compose -p vm1 --env-file env.local -f docker-compose.vm1.yml up -d
sleep 5
docker-compose -p vm2 --env-file env.local -f docker-compose.vm2.yml up -d
sleep 5
docker-compose -p vm3 --env-file env.local -f docker-compose.vm3.yml up -d
```

**Important:** The `-p vmX` flag ensures each compose stack uses a unique project name, preventing container recreation issues.

### 5. Verify the cluster

Wait 30-60 seconds for initialization, then check:

```bash
# Check Consul cluster (should show 3 alive servers)
docker exec consul-server-vm1 consul members

# Check Patroni cluster (should show 1 leader + 2 replicas)
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

# Test database connection to primary
docker exec patroni-postgres-vm1 psql -U postgres -c "SELECT version();"
```

Expected Patroni output:
```
+ Cluster: postgres-cluster -----+---------+-----------+----+-----------+
| Member               | Host    | Role    | State     | TL | Lag in MB |
+----------------------+---------+---------+-----------+----+-----------+
| patroni-postgres-vm1 | ...5432 | Leader  | running   |  2 |           |
| patroni-postgres-vm2 | ...5433 | Replica | streaming |  2 |         0 |
| patroni-postgres-vm3 | ...5434 | Replica | streaming |  2 |         0 |
+----------------------+---------+---------+-----------+----+-----------+
```

### 6. Access the cluster

**Consul UI:** http://localhost:8500

**PostgreSQL connections:**
- Primary (read/write): `localhost:5432`
- Replica 1 (read-only): `localhost:5433`
- Replica 2 (read-only): `localhost:5434`

**Patroni REST APIs:**
- VM1: http://localhost:8008
- VM2: http://localhost:8009
- VM3: http://localhost:8010

**Connection string example:**
```bash
psql "postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/postgres"
```

## Multi-VM Deployment (Production)

For production deployments across multiple VMs:

> **📋 Configuration Summary**: This repository is configured for **local development** by default. For production multi-VM deployment, you need to change:
> 
> | Component | Local Development | Production Multi-VM |
> |-----------|-------------------|---------------------|
> | **Docker Network** | `external: true` with shared `patroni-shared-bridge` | `driver: bridge` (each VM isolated) |
> | **Consul retry-join** | Container names (`consul-server-vm2`) | VM IP addresses (`192.168.1.102`) |
> | **Patroni addresses** | `host.docker.internal` | Actual VM IPs |
> | **Communication** | Via shared Docker network | Via VM network (L3) |
>
> The sections below guide you through making these changes.

### 1. Prerequisites per VM

On each VM (VM1, VM2, VM3):
```bash
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Clone this repository
git clone <your-repo-url>
cd posgresqlHA
```

### 2. Update network configuration for production

> **⚠️ Critical**: The repository is configured for single-host development with a shared network. For multi-VM production, you **must** change the network configuration in all three compose files.

Edit `docker-compose.vm1.yml`, `docker-compose.vm2.yml`, and `docker-compose.vm3.yml`:

**Current configuration (local development - shared network):**
```yaml
networks:
  patroni-network:
    external: true
    name: patroni-shared-bridge
```
This only works when all containers are on the **same Docker host**.

**For multi-VM production, change to:**
```yaml
networks:
  patroni-network:
    driver: bridge
```
Each VM will have its own isolated Docker bridge network. Containers communicate via VM IP addresses, not container names.

### 3. Update Consul retry-join addresses for production

> **⚠️ Note**: The repository currently uses **container names** (e.g., `consul-server-vm2`) for local development. For multi-VM production, you must change these to **actual VM IP addresses**.

Edit each compose file's Consul command section:

**Current configuration (local development - container names):**
```yaml
command: >
  agent -server -bootstrap-expect=3 -ui -client=0.0.0.0 -bind=0.0.0.0
  -retry-join=consul-server-vm2
  -retry-join=consul-server-vm3
  -datacenter=dc1 -data-dir=/consul/data
```

**For production - In docker-compose.vm1.yml (replace with real IPs):**
```yaml
command: >
  agent -server -bootstrap-expect=3 -ui -client=0.0.0.0 -bind=0.0.0.0
  -retry-join=192.168.1.102
  -retry-join=192.168.1.103
  -datacenter=dc1 -data-dir=/consul/data
```

**For production - In docker-compose.vm2.yml:**
```yaml
command: >
  agent -server -bootstrap-expect=3 -ui -client=0.0.0.0 -bind=0.0.0.0
  -retry-join=192.168.1.101
  -retry-join=192.168.1.103
  -datacenter=dc1 -data-dir=/consul/data
```

**For production - In docker-compose.vm3.yml:**
```yaml
command: >
  agent -server -bootstrap-expect=3 -ui -client=0.0.0.0 -bind=0.0.0.0
  -retry-join=192.168.1.101
  -retry-join=192.168.1.102
  -datacenter=dc1 -data-dir=/consul/data
```

Replace `192.168.1.10X` with your actual VM IP addresses (e.g., VM1=192.168.1.101, VM2=192.168.1.102, VM3=192.168.1.103).

### 4. Configure environment variables per VM

On each VM, create `env.local`:

**VM1:**
```bash
POSTGRES_PASSWORD=your_secure_password
REPLICATION_PASSWORD=your_secure_replication_password
CONNECT_ADDRESS_VM1=<VM1_IP>:5432
RESTAPI_CONNECT_ADDRESS_VM1=<VM1_IP>:8008
```

**VM2:**
```bash
POSTGRES_PASSWORD=your_secure_password
REPLICATION_PASSWORD=your_secure_replication_password
CONNECT_ADDRESS_VM2=<VM2_IP>:5432
RESTAPI_CONNECT_ADDRESS_VM2=<VM2_IP>:8008
```

**VM3:**
```bash
POSTGRES_PASSWORD=your_secure_password
REPLICATION_PASSWORD=your_secure_replication_password
CONNECT_ADDRESS_VM3=<VM3_IP>:5432
RESTAPI_CONNECT_ADDRESS_VM3=<VM3_IP>:8008
```

### 5. Deploy to each VM

Build and start on each VM:

```bash
# On all VMs
docker build -f docker/Dockerfile.patroni -t patroni-postgres .

# On VM1
docker-compose --env-file env.local -f docker-compose.vm1.yml up -d

# On VM2 (wait 10 seconds after VM1)
docker-compose --env-file env.local -f docker-compose.vm2.yml up -d

# On VM3 (wait 10 seconds after VM2)
docker-compose --env-file env.local -f docker-compose.vm3.yml up -d
```

## Operations

### View logs

```bash
# All logs for a VM
docker-compose -p vm1 -f docker-compose.vm1.yml logs -f

# Patroni logs only
docker logs -f patroni-postgres-vm1

# Consul logs only
docker logs -f consul-server-vm1
```

### Cluster management

```bash
# Check cluster status
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

# Trigger manual failover
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml failover

# Restart a Patroni node
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml restart patroni-postgres-vm1

# Reload configuration
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml reload patroni-postgres-vm1
```

### Database operations

```bash
# Connect to primary
docker exec -it patroni-postgres-vm1 psql -U postgres

# Check replication status
docker exec patroni-postgres-vm1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check if node is in recovery (replica)
docker exec patroni-postgres-vm2 psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### Stop the cluster

**Windows:**
```batch
.\stop-cluster.bat
```

**Linux/macOS:**
```bash
./stop-cluster.sh
```

Or manually:
```bash
docker-compose -p vm3 -f docker-compose.vm3.yml down
docker-compose -p vm2 -f docker-compose.vm2.yml down
docker-compose -p vm1 -f docker-compose.vm1.yml down
```

## Configuration Files

### Key files explained

- **`docker-compose.vm{1,2,3}.yml`**: Docker Compose definitions for each node
- **`docker/Dockerfile.patroni`**: Custom Patroni image with permission fixes
- **`docker/entrypoint.sh`**: Container startup script (fixes permissions, waits for Consul)
- **`patroni-config/patroni.yml`**: Patroni configuration template
- **`env.local`**: Environment variables (passwords, addresses)
- **`start-cluster.bat` / `stop-cluster.bat`**: Convenience scripts for cluster management

### Patroni configuration

The `patroni-config/patroni.yml` file is processed with `envsubst` at container startup, allowing environment variable substitution. Key settings:

```yaml
scope: postgres-cluster           # Cluster name
namespace: /patroni/              # Consul KV prefix

consul:
  host: consul-server-vm1         # Consul address
  port: 8500
  register_service: true          # Register in Consul catalog

bootstrap:
  dcs:
    ttl: 30                       # Leader lock TTL
    loop_wait: 10                 # Check interval
    retry_timeout: 30
    maximum_lag_on_failover: 1048576

postgresql:
  use_pg_rewind: true             # Enable pg_rewind for faster recovery
  parameters:
    max_connections: 100
    shared_buffers: 256MB
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Container recreation loop

**Symptom:** Containers repeatedly recreate on `docker-compose up -d`

**Solution:** Use unique project names with `-p vmX` flag:
```bash
docker-compose -p vm1 -f docker-compose.vm1.yml up -d
```

#### 2. Consul cluster not forming

**Symptom:** `consul members` shows "failed" or only 1 member

**Solution:** 

**For local development (single host):**
- Ensure all containers use shared network `patroni-shared-bridge`:
  ```bash
  docker network inspect patroni-shared-bridge
  ```
- Verify all compose files have:
  ```yaml
  networks:
    patroni-network:
      external: true
      name: patroni-shared-bridge
  ```
- Test container connectivity:
  ```bash
  docker exec consul-server-vm1 ping consul-server-vm2
  ```

**For production (multi-VM):**
- ⚠️ Shared network **does not work** across VMs - each VM has isolated Docker network
- Verify `retry-join` uses actual VM IP addresses (not container names)
- Verify network configuration uses `driver: bridge` (not `external: true`)
- Check firewall: Ports 8300-8302 must be open between VMs
- Test VM connectivity:
  ```bash
  # From VM1, test reach VM2
  ping 192.168.1.102
  telnet 192.168.1.102 8301
  ```

#### 3. Permission errors on replicas

**Symptom:** `FATAL: data directory has invalid permissions`

**Solution:** The image now runs as root and fixes permissions automatically. Rebuild image:
```bash
docker build --no-cache -f docker/Dockerfile.patroni -t patroni-postgres .
```

#### 4. Patroni YAML parsing errors

**Symptom:** `ValueError: invalid literal for int()`

**Solution:** Patroni's YAML parser doesn't support `${VAR:-default}` syntax. Use `envsubst` preprocessing (already configured in entrypoint).

#### 5. Windows line ending issues

**Symptom:** `/entrypoint.sh: no such file or directory`

**Solution:** Convert script to Unix line endings:
```bash
# Git Bash
dos2unix docker/entrypoint.sh

# PowerShell
$content = Get-Content docker/entrypoint.sh -Raw
$content.Replace("`r`n", "`n") | Set-Content docker/entrypoint.sh -NoNewline
```

#### 6. Patroni can't reach Consul

**Symptom:** Logs show "Waiting for Consul leader..."

**Solution:**
- Verify Consul is running: `docker exec consul-server-vm1 consul members`
- Test connectivity: `docker exec patroni-postgres-vm1 curl http://consul-server-vm1:8500/v1/status/leader`
- Check `CONSUL_HOST` in environment variables

### Health Checks

```bash
# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verify Consul cluster health
docker exec consul-server-vm1 consul operator raft list-peers

# Check Patroni replication lag
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

# View Patroni configuration
docker exec patroni-postgres-vm1 cat /tmp/patroni.yml
```

## Testing Failover

To test automatic failover:

```bash
# 1. Check current leader
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

# 2. Stop the leader (e.g., vm1)
docker stop patroni-postgres-vm1

# 3. Wait 30-60 seconds and check again (from vm2)
docker exec patroni-postgres-vm2 patronictl -c /tmp/patroni.yml list
# A new leader should be elected (vm2 or vm3)

# 4. Restart vm1 (it will become a replica)
docker start patroni-postgres-vm1

# 5. Verify vm1 rejoined as replica
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list
```

## HAProxy Integration (Optional)

HAProxy provides a single endpoint for your application and automatically routes traffic to the current primary.

### Deploy HAProxy

Create `docker-compose.haproxy.yml`:

```yaml
version: "3.9"

services:
  haproxy:
    image: haproxy:2.8-alpine
    container_name: haproxy
    restart: unless-stopped
    ports:
      - "5000:5000"  # Primary endpoint
      - "5001:5001"  # Replica endpoint
      - "7000:7000"  # Stats UI
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    networks:
      - patroni-network

networks:
  patroni-network:
    external: true
    name: patroni-shared-bridge
```

Start HAProxy:
```bash
docker-compose -f docker-compose.haproxy.yml up -d
```

### Access HAProxy

- **Stats UI**: http://localhost:7000 (admin/password)
- **Primary endpoint**: `localhost:5000`
- **Replica endpoint**: `localhost:5001`

Application connection:
```bash
psql "postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5000/postgres"
```

## Supabase Integration

### Option 1: Initialize Supabase Schema on Bootstrap

The Patroni bootstrap configuration includes `init-supabase-db.sql` which runs once on first cluster initialization. This creates the basic Supabase schema.

To customize:
1. Edit `scripts/init-supabase-db.sql`
2. Rebuild the cluster (delete volumes first)

### Option 2: Deploy Full Supabase Stack

Deploy Supabase services pointing to your HA PostgreSQL cluster:

```yaml
# In your Supabase configuration
DB_HOST: localhost  # or HAProxy host
DB_PORT: 5000       # HAProxy primary endpoint (or 5432 direct)
DB_USER: postgres
DB_PASSWORD: ${POSTGRES_PASSWORD}
DB_NAME: postgres
```

See [Supabase Docker deployment](https://supabase.com/docs/guides/hosting/docker) for full stack setup.

## Architecture Details

### Why Consul in Server Mode?

This setup runs Consul in **server mode** (not agent mode) on all three nodes:

- ✅ **Simplified architecture**: No separate Consul server cluster needed
- ✅ **Fewer moving parts**: Each VM runs exactly 2 containers
- ✅ **Direct access**: Patroni connects directly to local Consul server
- ✅ **High availability**: 3-node Consul cluster with Raft consensus
- ✅ **Quorum maintained**: Can tolerate 1 node failure

### Comparison: Docker vs Kubernetes

| Aspect | Docker (This Setup) | Kubernetes |
|--------|---------------------|------------|
| **Complexity** | Low - simple docker-compose files | High - StatefulSets, Services, ConfigMaps |
| **Learning Curve** | Minimal | Steep |
| **Resource Overhead** | Low | Medium-High |
| **Deployment Target** | VMs, single host | K8s cluster |
| **Management** | docker-compose, scripts | kubectl, Helm |
| **Service Discovery** | Container names, Consul | K8s Services, Consul DNS |
| **Scaling** | Manual | Automatic |
| **Best For** | VM deployments, simpler setups | Large-scale, cloud-native apps |

**Use Docker when:**
- Deploying on VMs or bare metal
- Want simplicity and control
- Don't need K8s features
- Team is familiar with Docker

**Use Kubernetes when:**
- Already have K8s infrastructure
- Need advanced orchestration
- Want operator patterns
- Require service mesh, auto-scaling, etc.

## Environment Variables Reference

### Required Variables

```bash
# PostgreSQL passwords (REQUIRED)
POSTGRES_PASSWORD=your_secure_postgres_password
REPLICATION_PASSWORD=your_secure_replication_password

# Node addressing (required for cluster formation)
CONNECT_ADDRESS_VM1=host.docker.internal:5432
CONNECT_ADDRESS_VM2=host.docker.internal:5433
CONNECT_ADDRESS_VM3=host.docker.internal:5434
RESTAPI_CONNECT_ADDRESS_VM1=host.docker.internal:8008
RESTAPI_CONNECT_ADDRESS_VM2=host.docker.internal:8009
RESTAPI_CONNECT_ADDRESS_VM3=host.docker.internal:8010
```

### Optional Variables

```bash
# Consul ACL token (leave empty for dev)
CONSUL_ACL_TOKEN=

# Consul datacenter name (default: dc1)
CONSUL_DATACENTER=dc1

# PostgreSQL version (default: 15)
POSTGRES_VERSION=15
```

## Performance Tuning

For production, adjust these PostgreSQL parameters in `patroni-config/patroni.yml`:

```yaml
postgresql:
  parameters:
    # Memory
    shared_buffers: 256MB              # 25% of RAM
    effective_cache_size: 1GB          # 50-75% of RAM
    work_mem: 16MB                     # RAM / max_connections / 4
    maintenance_work_mem: 128MB        # RAM / 16
    
    # Checkpointing
    checkpoint_completion_target: 0.9
    wal_buffers: 16MB
    
    # Connections
    max_connections: 100
    max_prepared_transactions: 100
    
    # Replication
    max_wal_senders: 10
    max_replication_slots: 10
    wal_level: replica
    hot_standby: on
```

After changing config:
```bash
# Reload configuration
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml reload patroni-postgres-vm1
```

## Security Best Practices

1. **Change default passwords**: Never use default passwords in production
2. **Use strong passwords**: Generate with `openssl rand -base64 32`
3. **Enable Consul ACLs**: Set `CONSUL_ACL_TOKEN` for production
4. **Restrict network access**: Use firewall rules to limit access
5. **Use TLS**: Enable SSL for PostgreSQL and Consul in production
6. **Regular backups**: Implement backup strategy with pg_basebackup or WAL archiving
7. **Monitor logs**: Set up log aggregation and monitoring
8. **Update regularly**: Keep Docker images and dependencies updated

## Backup and Recovery

### Backup

```bash
# Full backup of primary
docker exec patroni-postgres-vm1 pg_basebackup -U postgres -D /backup -Ft -z -P

# SQL dump
docker exec patroni-postgres-vm1 pg_dump -U postgres postgres > backup.sql

# Backup to host
docker exec patroni-postgres-vm1 pg_dump -U postgres postgres | gzip > backup-$(date +%Y%m%d).sql.gz
```

### Recovery

```bash
# Restore from SQL dump
docker exec -i patroni-postgres-vm1 psql -U postgres < backup.sql

# For full recovery, stop cluster and restore data directory
docker-compose -p vm1 -f docker-compose.vm1.yml down
# Restore /var/lib/docker/volumes/patroni-data-vm1/_data
docker-compose -p vm1 -f docker-compose.vm1.yml up -d
```

## Monitoring

### Basic Monitoring

```bash
# Cluster status
watch -n 5 'docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list'

# Replication lag
docker exec patroni-postgres-vm1 psql -U postgres -c "
  SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
  FROM pg_stat_replication;
"

# Database size
docker exec patroni-postgres-vm1 psql -U postgres -c "
  SELECT 
    pg_database.datname,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size
  FROM pg_database
  ORDER BY pg_database_size(pg_database.datname) DESC;
"
```

### Integration with Monitoring Tools

Patroni exposes REST API endpoints for monitoring:

- Health check: `http://localhost:8008/health`
- Leader check: `http://localhost:8008/leader`
- Replica check: `http://localhost:8008/replica`
- Metrics: `http://localhost:8008/metrics` (Prometheus format)

Example Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'patroni'
    static_configs:
      - targets: ['localhost:8008', 'localhost:8009', 'localhost:8010']
```

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## Support

For issues and questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review the [SETUP-CHECKLIST.md](SETUP-CHECKLIST.md) for common problems
- Open an issue on GitHub

## References

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Consul Documentation](https://www.consul.io/docs)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [HAProxy Documentation](http://www.haproxy.org/)

## License

MIT License - see LICENSE file for details.
