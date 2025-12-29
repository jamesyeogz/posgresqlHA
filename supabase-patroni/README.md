# Supabase PostgreSQL with Patroni and etcd

This directory contains a complete implementation of Supabase-compatible PostgreSQL with Patroni high availability support, inspired by Zalando's [Spilo](https://github.com/zalando/spilo) project.

## Architecture

This implementation combines:
- **PostgreSQL 16** with Supabase extensions
- **Patroni** for automatic failover and high availability
- **etcd/consul/zookeeper/kubernetes** as Distributed Configuration Store (DCS)
- **runit** for process supervision (like Spilo)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Supabase Patroni Architecture                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                   │
│   │   etcd1     │────│   etcd2     │────│   etcd3     │  (DCS Cluster)     │
│   │   :2379     │     │   :2379     │     │   :2379     │                   │
│   └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                   │
│          │                   │                   │                          │
│   ┌──────▼──────┐     ┌──────▼──────┐     ┌──────▼──────┐                   │
│   │  Patroni1   │     │  Patroni2   │     │  Patroni3   │                   │
│   │  (PRIMARY)  │     │  (REPLICA)  │     │  (REPLICA)  │                   │
│   │  ┌────────┐ │     │  ┌────────┐ │     │  ┌────────┐ │                   │
│   │  │ PG 16  │ │────│  │ PG 16  │ │────│  │ PG 16  │ │                   │
│   │  │Supabase│ │     │  │Supabase│ │     │  │Supabase│ │                   │
│   │  └────────┘ │     │  └────────┘ │     │  └────────┘ │                   │
│   │  :5432      │     │  :5432      │     │  :5432      │                   │
│   │  :8008(API) │     │  :8008(API) │     │  :8008(API) │                   │
│   └─────────────┘     └─────────────┘     └─────────────┘                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## How It Works (Like Spilo)

This implementation follows Zalando Spilo's proven architecture:

### 1. Build Scripts (`build_scripts/`)
- `base.sh` - Installs PostgreSQL and core dependencies
- `patroni.sh` - Installs Patroni with DCS support (etcd, consul, zookeeper, kubernetes)
- `extensions.sh` - Installs Supabase-specific PostgreSQL extensions

### 2. Configuration (`scripts/`)
- `configure_patroni.py` - Python script that generates Patroni configuration from environment variables
- `post_init.sh` - Runs after cluster bootstrap to initialize Supabase schemas
- `init-supabase-db.sql` - SQL script for Supabase database initialization

### 3. Process Management (`runit/`)
- Uses runit for process supervision (same as Spilo)
- `runit/patroni/run` - Service runner for Patroni

### 4. Entry Point (`launch.sh`)
- Main container entry point
- Sets up environment, generates config, starts services

## Quick Start

### Build the Image

```bash
# Build with default settings (PostgreSQL 16)
./build.sh

# Or build with custom name/tag
./build.sh supabase-patroni v1.0.0

# Or use docker build directly
docker build -t supabase-patroni:latest .
```

### Run with Docker Compose (Recommended)

Create a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  etcd1:
    image: quay.io/coreos/etcd:v3.5.9
    command:
      - etcd
      - --name=etcd1
      - --initial-advertise-peer-urls=http://etcd1:2380
      - --listen-peer-urls=http://0.0.0.0:2380
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://etcd1:2379
      - --initial-cluster=etcd1=http://etcd1:2380
      - --initial-cluster-state=new
    ports:
      - "2379:2379"

  patroni1:
    image: supabase-patroni:latest
    environment:
      PATRONI_NAME: patroni1
      PATRONI_SCOPE: supabase-ha
      PATRONI_ETCD_HOSTS: etcd1:2379
      POSTGRES_PASSWORD: your_secure_password
      REPLICATION_PASSWORD: repl_secure_password
    ports:
      - "5432:5432"
      - "8008:8008"
    depends_on:
      - etcd1
    volumes:
      - patroni1_data:/home/postgres/pgdata

  patroni2:
    image: supabase-patroni:latest
    environment:
      PATRONI_NAME: patroni2
      PATRONI_SCOPE: supabase-ha
      PATRONI_ETCD_HOSTS: etcd1:2379
      POSTGRES_PASSWORD: your_secure_password
      REPLICATION_PASSWORD: repl_secure_password
    ports:
      - "5433:5432"
      - "8009:8008"
    depends_on:
      - etcd1
      - patroni1
    volumes:
      - patroni2_data:/home/postgres/pgdata

volumes:
  patroni1_data:
  patroni2_data:
```

Start the cluster:

```bash
docker-compose up -d
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PATRONI_NAME` | Unique node name | hostname |
| `PATRONI_SCOPE` | Cluster name | postgres-ha |
| `PATRONI_ETCD_HOSTS` | Comma-separated etcd hosts | - |
| `PATRONI_ETCD_URL` | Single etcd URL | - |
| `PATRONI_CONSUL_HOST` | Consul host | - |
| `PATRONI_ZOOKEEPER_HOSTS` | ZooKeeper hosts | - |
| `POSTGRES_PASSWORD` | PostgreSQL superuser password | postgres |
| `REPLICATION_PASSWORD` | Replication user password | replication |
| `PGVERSION` | PostgreSQL version | 16 |
| `PATRONI_FOREGROUND` | Run Patroni in foreground | false |

## Supabase Extensions

The image includes these Supabase-compatible extensions:

| Extension | Description | Status |
|-----------|-------------|--------|
| `uuid-ossp` | UUID generation | ✅ Included |
| `pgcrypto` | Cryptographic functions | ✅ Included |
| `pg_stat_statements` | Query monitoring | ✅ Included |
| `pgjwt` | JWT token generation | ✅ Installed |
| `pgsodium` | Encryption (Vault) | ✅ Installed |
| `pgvector` | Vector similarity search | ✅ Installed |
| `pg_cron` | Scheduled jobs | ✅ Installed |
| `http` | HTTP client | ✅ Installed |
| `pg_hashids` | Short unique IDs | ✅ Installed |

## Cluster Management

### Check Cluster Status

```bash
# Using patronictl
docker exec patroni1 patronictl list

# Using REST API
curl http://localhost:8008/

# Using the status script
docker exec patroni1 /scripts/cluster_status.sh
```

### Failover/Switchover

```bash
# Graceful switchover to specific node
docker exec patroni1 patronictl switchover --master patroni1 --candidate patroni2

# Automatic failover
docker exec patroni1 patronictl failover --candidate patroni2
```

### Check Replication

```bash
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## REST API Endpoints

Patroni exposes these endpoints on port 8008:

| Endpoint | Description |
|----------|-------------|
| `GET /` | Node info |
| `GET /health` | Health check |
| `GET /primary` | Returns 200 if primary |
| `GET /replica` | Returns 200 if replica |
| `GET /read-only` | Returns 200 if read-only |
| `GET /cluster` | Cluster info |

## Directory Structure

```
supabase-patroni/
├── Dockerfile              # Main Dockerfile
├── build.sh                # Build script
├── launch.sh               # Container entry point
├── README.md               # This file
├── build_scripts/
│   ├── base.sh            # PostgreSQL installation
│   ├── patroni.sh         # Patroni installation
│   └── extensions.sh      # Supabase extensions
├── scripts/
│   ├── configure_patroni.py    # Config generator
│   ├── post_init.sh            # Post-bootstrap script
│   ├── patroni_wait.sh         # Wait for Patroni
│   ├── cluster_status.sh       # Status script
│   ├── healthcheck.sh          # Health check
│   └── init-supabase-db.sql    # Supabase init SQL
└── runit/
    └── patroni/
        ├── run            # Service runner
        └── finish         # Service finish script
```

## Comparison with Zalando Spilo

| Feature | This Image | Spilo |
|---------|-----------|-------|
| PostgreSQL | 16 | 13-17 |
| Patroni | ✅ | ✅ |
| etcd Support | ✅ | ✅ |
| Consul Support | ✅ | ✅ |
| ZooKeeper Support | ✅ | ✅ |
| Kubernetes DCS | ✅ | ✅ |
| runit Process Manager | ✅ | ✅ |
| WAL-E/WAL-G | ❌ | ✅ |
| Supabase Extensions | ✅ | ❌ |
| pg_cron | ✅ | ✅ |
| TimescaleDB | ❌ | ✅ |

## Kubernetes Deployment

For Kubernetes, use the Patroni Kubernetes DCS:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: supabase-patroni
spec:
  serviceName: supabase-patroni
  replicas: 3
  template:
    spec:
      containers:
      - name: patroni
        image: supabase-patroni:latest
        env:
        - name: PATRONI_SCOPE
          value: supabase-ha
        - name: PATRONI_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: KUBERNETES_SERVICE_HOST
          value: "kubernetes.default.svc"
        # ... other env vars
```

## Troubleshooting

### Patroni won't start

1. Check etcd connectivity:
   ```bash
   curl http://etcd1:2379/health
   ```

2. Check Patroni logs:
   ```bash
   docker logs patroni1
   ```

3. Verify configuration:
   ```bash
   docker exec patroni1 cat /run/patroni.yml
   ```

### Nodes not joining cluster

1. Ensure all nodes can reach etcd
2. Verify `PATRONI_SCOPE` is the same on all nodes
3. Check network connectivity between nodes

### Extensions not loading

1. Check `shared_preload_libraries` in Patroni config
2. Verify extension files exist:
   ```bash
   docker exec patroni1 ls /usr/lib/postgresql/16/lib/*.so
   ```

## License

This project is provided under the same license as PostgreSQL.
