# Agent 1: Per-VM Docker Compose Files

## Overview

This document describes the per-VM docker-compose files created for the PostgreSQL HA cluster migration from etcd to Consul. Each VM now runs its own docker-compose file with a Patroni PostgreSQL node and Consul agent.

## Files Created

### docker-compose.vm1.yml

- **VM1 Patroni PostgreSQL node** on port 5432
- **VM1 Patroni API** on port 8008
- **VM1 Consul agent** on port 8500
- **Network**: 172.20.0.0/16

### docker-compose.vm2.yml

- **VM2 Patroni PostgreSQL node** on port 5433
- **VM2 Patroni API** on port 8009
- **VM2 Consul agent** on port 8501 (host port)
- **Network**: 172.21.0.0/16

### docker-compose.vm3.yml

- **VM3 Patroni PostgreSQL node** on port 5434
- **VM3 Patroni API** on port 8010
- **VM3 Consul agent** on port 8502 (host port)
- **Network**: 172.22.0.0/16

## Key Features

### Consul Agent Configuration

Each VM runs a Consul agent that:

- Connects to the Kubernetes Consul cluster
- Provides local service discovery
- Handles health checks
- Maintains local configuration

### Patroni PostgreSQL Configuration

Each Patroni node:

- Uses Consul as the Distributed Configuration Store (DCS)
- Connects to the local Consul agent
- Maintains PostgreSQL replication
- Provides REST API for cluster management

### Port Assignments

- **VM1**: PostgreSQL (5432), Patroni API (8008), Consul (8500)
- **VM2**: PostgreSQL (5433), Patroni API (8009), Consul (8501)
- **VM3**: PostgreSQL (5434), Patroni API (8010), Consul (8502)

## Deployment Instructions

### Prerequisites

1. Kubernetes cluster with Consul cluster deployed
2. Docker and Docker Compose on each VM
3. Updated `patroni.env` file with Consul configuration

### Deploy on VM1

```bash
# Copy files to VM1
scp docker-compose.vm1.yml patroni.env vm1:/path/to/project/

# Deploy on VM1
cd /path/to/project
docker-compose -f docker-compose.vm1.yml up -d
```

### Deploy on VM2

```bash
# Copy files to VM2
scp docker-compose.vm2.yml patroni.env vm2:/path/to/project/

# Deploy on VM2
cd /path/to/project
docker-compose -f docker-compose.vm2.yml up -d
```

### Deploy on VM3

```bash
# Copy files to VM3
scp docker-compose.vm3.yml patroni.env vm3:/path/to/project/

# Deploy on VM3
cd /path/to/project
docker-compose -f docker-compose.vm3.yml up -d
```

## Environment Variables

The `patroni.env` file now includes:

- `CONSUL_HOST`: Consul agent endpoint (consul-agent:8500)
- `CONSUL_DATACENTER`: Datacenter name (dc1)
- `CONSUL_ACL_TOKEN`: Optional ACL token for authentication

## Health Checks

### Consul Agent Health

```bash
# Check Consul agent status
docker exec consul-agent-vm1 consul members

# Check Consul agent health
docker exec consul-agent-vm1 consul catalog services
```

### Patroni Cluster Health

```bash
# Check Patroni cluster status
docker exec patroni-postgres-vm1 patronictl list

# Check Patroni configuration
docker exec patroni-postgres-vm1 patronictl show-config
```

## Troubleshooting

### Common Issues

#### Consul Agent Cannot Connect to Cluster

- Verify Kubernetes Consul cluster is running
- Check network connectivity to Kubernetes cluster
- Verify Consul server endpoints in retry_join configuration

#### Patroni Cannot Connect to Consul

- Check Consul agent health: `docker exec consul-agent-vm1 consul members`
- Verify CONSUL_HOST environment variable
- Check Patroni logs: `docker logs patroni-postgres-vm1`

#### Port Conflicts

- Ensure each VM uses different host ports
- Check for existing services using the same ports
- Verify port mappings in docker-compose files

### Logs

```bash
# Consul agent logs
docker logs consul-agent-vm1

# Patroni logs
docker logs patroni-postgres-vm1

# Combined logs
docker-compose -f docker-compose.vm1.yml logs -f
```

## Next Steps

1. **Agent 2**: Update Patroni configuration to use Consul DCS
2. **Agent 3**: Deploy Consul cluster in Kubernetes
3. **Agent 4**: Update documentation and setup scripts

## Dependencies

- Kubernetes Consul cluster must be deployed first
- Patroni configuration must be updated to use Consul
- HAProxy must be configured to use Consul service discovery
