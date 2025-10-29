# Agent Task Assignment - PostgreSQL HA with Consul

## Overview

This document outlines the tasks for setting up a PostgreSQL HA cluster using Consul as the distributed configuration store and implementing per-VM deployment architecture. This is a clean Consul-based setup without any migration from etcd.

## Task Assignments

### Agent 1: Docker Compose File Splitting

**Status**: Completed ✅
**Files Created**:

- `docker-compose.vm1.yml` - VM1 Patroni PostgreSQL node ✅
- `docker-compose.vm2.yml` - VM2 Patroni PostgreSQL node ✅
- `docker-compose.vm3.yml` - VM3 Patroni PostgreSQL node ✅
- `AGENT1-README.md` - Documentation for per-VM deployment ✅
- `README.md` - Updated main documentation with per-VM deployment instructions ✅

**Requirements**:

- Each file should contain one Patroni PostgreSQL service ✅
- Include Consul agent service in each compose file ✅
- Use consistent networking between containers ✅
- Port mapping: VM1 (5432), VM2 (5433), VM3 (5434) ✅
- Patroni API ports: VM1 (8008), VM2 (8009), VM3 (8010) ✅
- Environment variables for Consul connection instead of etcd ✅
- Update main README.md with comprehensive per-VM deployment steps ✅

**Template Structure**:

```yaml
version: "3.9"
services:
  consul-agent:
    image: consul:1.16
    # Consul agent configuration

  patroni-postgres:
    build:
      context: .
      dockerfile: docker/Dockerfile.patroni
    # Patroni configuration with Consul
```

### Agent 2: Patroni Configuration Migration

**Status**: Completed ✅
**Files Modified**:

- `patroni-config/patroni.yml` ✅
- `patroni.env` ✅

**Requirements**:

- Replace etcd configuration with Consul ✅
- Update DCS (Distributed Configuration Store) settings ✅
- Maintain all existing PostgreSQL parameters ✅
- Update connection settings for Consul ✅
- Add Consul datacenter configuration ✅
- Add ACL token support for authentication ✅
- Improve YAML formatting consistency ✅

**Changes Implemented**:

```yaml
# Replaced etcd section with:
consul:
  host: ${CONSUL_HOST:-consul-agent:8500}
  port: 8500
  scheme: http
  verify: false
  checks: []
  register_service: true
```

**Environment Variables Added**:

- `CONSUL_HOST`: Consul cluster endpoint (defaults to consul-agent:8500)
- `CONSUL_DATACENTER`: Datacenter name (dc1)
- `CONSUL_ACL_TOKEN`: ACL token for authentication (optional)

### Agent 3: Kubernetes Consul Cluster

**Status**: Completed ✅
**Files Created/Modified**:

- `k8s/consul-cluster.yaml` (created) ✅
- `k8s/haproxy-deployment.yaml` (modify - pending)
- `k8s/etcd-cluster.yaml` (not needed - Consul-based setup)

**Requirements**:

- Create Consul cluster StatefulSet with 3 replicas ✅
- Include Consul services (headless, client, loadbalancer) ✅
- Update HAProxy to use Consul for service discovery (pending)
- Ensure HAProxy remains LoadBalancer type (not NodePort) (pending)
- Remove all etcd references ✅

### Agent 4: Documentation and Scripts Update

**Status**: Completed ✅
**Files Modified**:

- `README.md` ✅
- `scripts/setup.sh` ✅

**Requirements**:

- Update architecture diagrams to show Consul instead of etcd ✅
- Update setup instructions for Consul deployment ✅
- Modify setup script to deploy Consul cluster ✅
- Update troubleshooting section ✅
- Document per-VM deployment approach ✅

## Current Progress

### Completed ✅

- [x] Analyzed current setup and decided on Consul-based architecture
- [x] Agent 1: Created per-VM docker-compose files with Consul agents
- [x] Agent 1: Updated patroni.env with Consul configuration variables
- [x] Agent 1: Created documentation for per-VM deployment approach
- [x] Agent 1: Updated main README.md with comprehensive per-VM deployment instructions
- [x] Agent 2: Configured Patroni to use Consul as DCS
- [x] Agent 3: Created Consul cluster Kubernetes manifests
- [x] Agent 4: Updated documentation and setup scripts for Consul
- [x] Agent 4: Added comprehensive troubleshooting section
- [x] Agent 4: Documented per-VM deployment approach

### In Progress 🔄

- [ ] Agent 3: Update HAProxy configuration for Consul service discovery

### Pending ⏳

- [ ] Integration testing and validation
- [ ] Create simplified setup script for Consul-only deployment
- [ ] Update HAProxy to use Consul for dynamic backend discovery

## Technical Notes

### Consul-Based Architecture

This setup uses Consul as the primary distributed configuration store from the beginning, providing:

1. **Patroni DCS**: Consul serves as the distributed configuration store for Patroni
2. **Service Discovery**: HAProxy uses Consul for dynamic backend discovery
3. **Health Checks**: Consul provides health checks for PostgreSQL nodes
4. **Per-VM Agents**: Each VM runs a Consul agent connected to the cluster
5. **No Migration**: Clean setup without any etcd dependencies

### Port Assignments

- **PostgreSQL**: VM1(5432), VM2(5433), VM3(5434)
- **Patroni API**: VM1(8008), VM2(8009), VM3(8010)
- **Consul**: 8500 (HTTP), 8300 (Server RPC), 8301 (Serf LAN), 8302 (Serf WAN)

### Environment Variables

- `CONSUL_HOST`: Consul cluster endpoint (default: consul-agent:8500)
- `CONSUL_DATACENTER`: Datacenter name (default: dc1)
- `CONSUL_ACL_TOKEN`: ACL token for authentication (optional, disabled by default)
- `POSTGRES_PASSWORD`: PostgreSQL superuser password
- `REPLICATION_PASSWORD`: PostgreSQL replication password

## Next Steps

1. ✅ Agent 1: Complete per-VM docker-compose files
2. ✅ Agent 2: Configure Patroni with Consul DCS
3. ✅ Agent 3: Create Consul Kubernetes manifests
4. ✅ Agent 4: Update documentation and scripts
5. 🔄 Update HAProxy for Consul service discovery
6. ⏳ Integration testing and validation
7. ⏳ Create simplified deployment script

## Dependencies

- Consul cluster must be deployed before Patroni nodes
- HAProxy configuration depends on Consul service discovery
- Per-VM deployment requires proper network connectivity
- All VMs must be able to reach the Consul cluster
- Documentation reflects the Consul-based architecture
