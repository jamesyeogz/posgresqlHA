# PostgreSQL HA Cluster with Patroni + Supabase

A production-ready PostgreSQL High Availability cluster using Patroni (Spilo) with etcd, designed to work with Supabase.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           3-Node HA Cluster                                  │
├─────────────────────┬─────────────────────┬─────────────────────────────────┤
│        VM1          │        VM2          │              VM3                │
│  ┌───────────────┐  │  ┌───────────────┐  │  ┌───────────────┐              │
│  │   etcd1       │◄─┼──┤   etcd2       │◄─┼──┤   etcd3       │              │
│  │   :2379/2380  │  │  │   :2379/2380  │  │  │   :2379/2380  │              │
│  └───────┬───────┘  │  └───────┬───────┘  │  └───────┬───────┘              │
│          │          │          │          │          │                      │
│  ┌───────▼───────┐  │  ┌───────▼───────┐  │  ┌───────▼───────┐              │
│  │  Patroni1     │  │  │  Patroni2     │  │  │  Patroni3     │              │
│  │  (PRIMARY)    │  │  │  (REPLICA)    │  │  │  (REPLICA)    │              │
│  │  :5432/:8008  │  │  │  :5432/:8008  │  │  │  :5432/:8008  │              │
│  └───────────────┘  │  └───────────────┘  │  └───────────────┘              │
└─────────────────────┴─────────────────────┴─────────────────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────┐
                        │     HAProxy       │
                        │   :5000 (R/W)     │
                        │   :5001 (R/O)     │
                        └─────────┬─────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │     Supabase      │
                        │   (Auth, API,     │
                        │    Storage, etc)  │
                        └───────────────────┘
```

## Prerequisites

- 3 VMs (Linux) with Docker and Docker Compose installed
- Network connectivity between all VMs on ports:
  - `2379`, `2380` (etcd)
  - `5432` (PostgreSQL)
  - `8008` (Patroni REST API)
- Static IPs for each VM

## Quick Start

### 0. Build the Custom Docker Image (Required First)

The cluster uses a custom Docker image with Supabase extensions. Build it before deploying:

**Linux/macOS:**

```bash
# Build the custom Supabase-Patroni image
chmod +x docker/build.sh
./docker/build.sh

# Or with custom tag
./docker/build.sh supabase-patroni:v1.0
```

**Windows PowerShell:**

```powershell
# Build the custom Supabase-Patroni image
.\docker\build.ps1

# Or with custom tag
.\docker\build.ps1 -Tag "supabase-patroni:v1.0"
```

**Transfer image to all VMs:**

```bash
# Save image to file
docker save supabase-patroni:latest -o supabase-patroni.tar

# Copy to other VMs (use scp, rsync, etc.)
scp supabase-patroni.tar user@vm2:/path/
scp supabase-patroni.tar user@vm3:/path/

# Load on each VM
docker load -i supabase-patroni.tar
```

**Or use a registry:**

```bash
# Tag and push to your registry
docker tag supabase-patroni:latest your-registry.com/supabase-patroni:latest
docker push your-registry.com/supabase-patroni:latest

# On each VM, pull the image
docker pull your-registry.com/supabase-patroni:latest
docker tag your-registry.com/supabase-patroni:latest supabase-patroni:latest
```

### 1. Set Environment Variables (on each VM)

**VM1:**

```bash
export NODE1_IP=192.168.1.10   # Replace with actual VM1 IP
export NODE2_IP=192.168.1.11   # Replace with actual VM2 IP
export NODE3_IP=192.168.1.12   # Replace with actual VM3 IP
export POSTGRES_PASSWORD=your_secure_password
export REPLICATION_PASSWORD=your_replication_password
```

**VM2 & VM3:** Same variables (all VMs need to know all IPs)

### 2. Copy Files to Each VM

Copy these files to each VM:

- `docker-compose.vm1.yml` → VM1
- `docker-compose.vm2.yml` → VM2
- `docker-compose.vm3.yml` → VM3

> **Note:** The `scripts/` folder is no longer needed on VMs - scripts are embedded in the Docker image.

### 3. Start the Cluster

**Start VM1 first (will become primary):**

```bash
# On VM1
docker-compose -f docker-compose.vm1.yml up -d
```

**Wait 30 seconds, then start VM2 and VM3:**

```bash
# On VM2
docker-compose -f docker-compose.vm2.yml up -d

# On VM3
docker-compose -f docker-compose.vm3.yml up -d
```

### 4. Verify Cluster Status

```bash
# On any VM
docker exec patroni1 patronictl list
```

Expected output:

```
+ Cluster: postgres-ha ----+---------+---------+----+-----------+
| Member    | Host         | Role    | State   | TL | Lag in MB |
+-----------+--------------+---------+---------+----+-----------+
| patroni1  | 192.168.1.10 | Leader  | running |  1 |           |
| patroni2  | 192.168.1.11 | Replica | running |  1 |         0 |
| patroni3  | 192.168.1.12 | Replica | running |  1 |         0 |
+-----------+--------------+---------+---------+----+-----------+
```

## Supabase Extensions

The custom Docker image includes these PostgreSQL extensions for Supabase:

| Extension            | Purpose                     | Status       |
| -------------------- | --------------------------- | ------------ |
| `uuid-ossp`          | UUID generation             | ✅ Core      |
| `pgcrypto`           | Cryptographic functions     | ✅ Core      |
| `pg_stat_statements` | Query monitoring            | ✅ Core      |
| `pgjwt`              | JWT token generation (Auth) | ✅ Installed |
| `pgsodium`           | Encryption (Vault)          | ✅ Installed |
| `pgvector`           | AI/ML vector search         | ✅ Installed |
| `pg_cron`            | Scheduled jobs              | ✅ Installed |
| `http`               | HTTP client                 | ✅ Installed |
| `pg_hashids`         | Short unique IDs            | ✅ Installed |
| `pg_graphql`         | GraphQL API                 | ⚠️ Optional  |
| `pg_net`             | Async HTTP                  | ⚠️ Optional  |

**Verify installed extensions:**

```bash
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_available_extensions WHERE name IN ('pgvector', 'pgsodium', 'pgjwt', 'pg_cron', 'http');"
```

## Supabase Database Initialization

The Supabase init script (`scripts/init-supabase-db.sql`) runs automatically when the cluster bootstraps for the first time. It creates:

- Required schemas: `auth`, `storage`, `realtime`, `_analytics`, `_realtime`, etc.
- Required roles: `anon`, `authenticated`, `service_role`, etc.
- Core tables: `auth.users`, `auth.sessions`, `storage.buckets`, etc.
- Helper functions: `auth.uid()`, `auth.role()`, `auth.email()`
- Row Level Security (RLS) policies
- All Supabase extensions (pgjwt, pgsodium, pgvector, pg_cron, http, etc.)

### Manual Initialization (if needed)

If you need to run the init script manually:

```bash
# Connect to primary
docker exec -it patroni1 psql -U postgres -d postgres -f /scripts/init-supabase-db.sql
```

### Verify Supabase Schema

```bash
docker exec patroni1 psql -U postgres -c "\dn"  # List schemas
docker exec patroni1 psql -U postgres -c "\dt auth.*"  # List auth tables
docker exec patroni1 psql -U postgres -c "\du"  # List roles
```

## Deploying Supabase

### Option 1: Docker Compose (Single Node)

Create a `docker-compose.supabase.yml`:

```yaml
version: "3.9"

services:
  supabase-studio:
    image: supabase/studio:latest
    ports:
      - "3000:3000"
    environment:
      STUDIO_PG_META_URL: http://supabase-meta:8080
      SUPABASE_URL: http://supabase-kong:8000
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_KEY}

  supabase-kong:
    image: kong:2.8.1
    ports:
      - "8000:8000"
      - "8443:8443"
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
    volumes:
      - ./kong.yml:/var/lib/kong/kong.yml:ro

  supabase-auth:
    image: supabase/gotrue:v2.143.0
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      API_EXTERNAL_URL: ${API_EXTERNAL_URL}
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@${NODE1_IP}:5432/postgres
      GOTRUE_SITE_URL: ${SITE_URL}
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_JWT_EXP: 3600
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated

  supabase-rest:
    image: postgrest/postgrest:v11.2.0
    environment:
      PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@${NODE1_IP}:5432/postgres
      PGRST_DB_SCHEMAS: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_USE_LEGACY_GUCS: "false"

  supabase-realtime:
    image: supabase/realtime:v2.25.50
    environment:
      PORT: 4000
      DB_HOST: ${NODE1_IP}
      DB_PORT: 5432
      DB_USER: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_NAME: postgres
      DB_SSL: "false"
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}

  supabase-storage:
    image: supabase/storage-api:v0.43.11
    environment:
      ANON_KEY: ${ANON_KEY}
      SERVICE_KEY: ${SERVICE_KEY}
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@${NODE1_IP}:5432/postgres
      PGRST_JWT_SECRET: ${JWT_SECRET}
      STORAGE_BACKEND: file
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
    volumes:
      - supabase-storage-data:/var/lib/storage

  supabase-meta:
    image: supabase/postgres-meta:v0.68.0
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: ${NODE1_IP}
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: postgres
      PG_META_DB_USER: postgres
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}

volumes:
  supabase-storage-data:
```

### Option 2: Kubernetes (Helm)

Use the official Supabase Helm chart with external PostgreSQL:

```bash
# Add Supabase Helm repo
helm repo add supabase https://supabase-community.github.io/supabase-kubernetes/

# Create values file
cat > supabase-values.yaml << EOF
global:
  postgresql:
    host: ${NODE1_IP}  # Or HAProxy IP
    port: 5432
    user: postgres
    password: ${POSTGRES_PASSWORD}
    database: postgres

studio:
  enabled: true

auth:
  enabled: true

rest:
  enabled: true

realtime:
  enabled: true

storage:
  enabled: true
EOF

# Install
helm install supabase supabase/supabase -f supabase-values.yaml
```

## HAProxy Setup (Optional)

For load balancing and automatic failover detection:

**`haproxy/haproxy.cfg`:**

```
global
    maxconn 1000

defaults
    mode tcp
    timeout connect 10s
    timeout client 30s
    timeout server 30s

frontend postgres_rw
    bind *:5000
    default_backend postgres_primary

frontend postgres_ro
    bind *:5001
    default_backend postgres_replicas

backend postgres_primary
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server patroni1 ${NODE1_IP}:5432 check port 8008
    server patroni2 ${NODE2_IP}:5432 check port 8008
    server patroni3 ${NODE3_IP}:5432 check port 8008

backend postgres_replicas
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server patroni1 ${NODE1_IP}:5432 check port 8008
    server patroni2 ${NODE2_IP}:5432 check port 8008
    server patroni3 ${NODE3_IP}:5432 check port 8008

listen stats
    bind *:7000
    mode http
    stats enable
    stats uri /
```

Run HAProxy:

```bash
docker run -d --name haproxy \
  --network host \
  -v $(pwd)/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
  haproxy:2.8
```

## Common Commands

```bash
# Check cluster status
docker exec patroni1 patronictl list

# Failover to specific node
docker exec patroni1 patronictl failover --candidate patroni2

# Switchover (graceful)
docker exec patroni1 patronictl switchover --master patroni1 --candidate patroni2

# Check replication lag
docker exec patroni1 psql -U postgres -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

# View Patroni logs
docker logs patroni1 --tail 100 -f

# Connect to PostgreSQL
docker exec -it patroni1 psql -U postgres
```

## Troubleshooting

### Patroni nodes not forming cluster

1. Check all VMs can reach each other:

   ```bash
   # From VM1
   curl http://${NODE2_IP}:8008/health
   curl http://${NODE3_IP}:8008/health
   ```

2. Check etcd cluster health:

   ```bash
   docker exec etcd1 etcdctl endpoint health --cluster
   docker exec etcd1 etcdctl member list
   ```

3. Check Patroni logs:
   ```bash
   docker logs patroni1 --tail 100
   ```

### Reset cluster (delete all data)

```bash
# Stop all services
docker-compose -f docker-compose.vm1.yml down -v
docker-compose -f docker-compose.vm2.yml down -v
docker-compose -f docker-compose.vm3.yml down -v

# Remove volumes
docker volume rm $(docker volume ls -q | grep patroni)
docker volume rm $(docker volume ls -q | grep etcd)
```

## Environment Variables Reference

| Variable               | Description                   | Required | Default                   |
| ---------------------- | ----------------------------- | -------- | ------------------------- |
| `NODE1_IP`             | IP address of VM1             | Yes      | -                         |
| `NODE2_IP`             | IP address of VM2             | Yes      | -                         |
| `NODE3_IP`             | IP address of VM3             | Yes      | -                         |
| `POSTGRES_PASSWORD`    | PostgreSQL superuser password | Yes      | -                         |
| `REPLICATION_PASSWORD` | Replication user password     | Yes      | -                         |
| `PATRONI_IMAGE`        | Custom Patroni Docker image   | No       | `supabase-patroni:latest` |

**To use original Spilo image (without Supabase extensions):**

```bash
export PATRONI_IMAGE=ghcr.io/zalando/spilo-16:3.2-p2
```

## Security Notes

- Change default passwords before production use
- Use TLS for PostgreSQL connections in production
- Restrict network access using firewalls
- Use secrets management (Vault, K8s secrets) for credentials
