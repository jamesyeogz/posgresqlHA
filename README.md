# Patroni PostgreSQL HA Cluster with Supabase Integration

This repository provides a complete High Availability PostgreSQL setup using Patroni, Consul, HAProxy, and Supabase integration. The architecture separates concerns by running the database cluster in Docker while orchestrating Consul and HAProxy in Kubernetes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   Consul Cluster│    │        HAProxy                  │ │
│  │   (StatefulSet) │    │      (Deployment)               │ │
│  │                 │    │                                 │ │
│  │ consul-0:8500   │    │ ┌─────────────────────────────┐ │ │
│  │ consul-1:8500   │◄───┤ │ Load Balances Traffic to    │ │ │
│  │ consul-2:8500   │    │ │ Docker Patroni Containers   │ │ │
│  │                 │    │ └─────────────────────────────┘ │ │
│  │ NodePort:32500  │    │                                 │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                Supabase Services                        │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐      │ │
│  │  │ Studio  │ │  Auth   │ │  REST   │ │ Storage │ ...  │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                Docker Host (Per-VM Deployment)              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Patroni PostgreSQL Cluster                │ │
│  │                                                         │ │
│  │ VM1: patroni-postgres:5432 (Primary)                  │ │
│  │ VM2: patroni-postgres:5433 (Replica)                  │ │
│  │ VM3: patroni-postgres:5434 (Replica)                  │ │
│  │                                                         │ │
│  │ Each VM runs:                                          │ │
│  │ - Consul Agent (connects to cluster)                  │ │
│  │ - Patroni PostgreSQL                                   │ │
│  │                                                         │ │
│  │ Connected to Consul: 192.168.49.2:32500               │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Docker and Docker Compose
- Kubernetes cluster (Minikube, kind, or cloud provider)
- kubectl configured to access your cluster
- Helm 3.x (for Supabase deployment)

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd postgresql
```

### 2. Start Minikube (if using Minikube)

```bash
minikube start
```

### 3. Deploy Consul Cluster

```bash
kubectl apply -f k8s/consul-cluster.yaml
```

### 4. Deploy HAProxy Load Balancer

```bash
kubectl apply -f k8s/haproxy-deployment.yaml
```

### 5. Build and Start Patroni Cluster (Per-VM Deployment)

```bash
# Build the Patroni Docker image (on each VM)
docker build -f docker/Dockerfile.patroni -t patroni-postgres .

# Copy environment file to each VM
scp patroni.env vm1:/path/to/project/
scp patroni.env vm2:/path/to/project/
scp patroni.env vm3:/path/to/project/

# Deploy on VM1 (Primary) - Port 5432
ssh vm1 "cd /path/to/project && docker-compose -f docker-compose.vm1.yml up -d"

# Deploy on VM2 (Replica) - Port 5433
ssh vm2 "cd /path/to/project && docker-compose -f docker-compose.vm2.yml up -d"

# Deploy on VM3 (Replica) - Port 5434
ssh vm3 "cd /path/to/project && docker-compose -f docker-compose.vm3.yml up -d"
```

### 6. Deploy Supabase (Optional)

```bash
# Add Supabase Helm repository
helm repo add supabase https://supabase.github.io/supabase-kubernetes
helm repo update

# Deploy Supabase with Patroni integration
helm install supabase supabase/supabase -f supabase-helm/values-patroni.yaml
```

## Detailed Setup Guide

### Step 1: Understanding the Components

#### Patroni PostgreSQL Cluster

- **Purpose**: High-availability PostgreSQL cluster with automatic failover
- **Components**: 3 PostgreSQL nodes managed by Patroni
- **Ports**: 5432 (primary), 5433-5434 (replicas), 8008-8010 (Patroni API)

#### Consul Cluster

- **Purpose**: Distributed key-value store and service discovery for Patroni cluster coordination
- **Deployment**: Kubernetes StatefulSet with 3 replicas
- **Access**: NodePort service on port 32500
- **Features**: Service discovery, health checks, distributed locking

#### HAProxy Load Balancer

- **Purpose**: Load balancing and connection routing
- **Features**: Health checks, automatic failover detection
- **Access**: Kubernetes services for different connection types

### Step 2: Kubernetes Components Setup

#### Deploy Consul Cluster

The Consul cluster provides distributed consensus and service discovery for Patroni:

```bash
kubectl apply -f k8s/consul-cluster.yaml
```

This creates:

- StatefulSet with 3 Consul server instances
- Headless service for cluster communication
- NodePort service for external access
- Persistent volumes for data storage
- Consul UI service for management interface

#### Deploy HAProxy

HAProxy provides intelligent load balancing:

```bash
kubectl apply -f k8s/haproxy-deployment.yaml
```

Features:

- Automatic host IP detection via init container
- Health checks against Patroni REST API
- Separate endpoints for read/write and read-only traffic

### Step 3: Patroni PostgreSQL Cluster

#### Build the Docker Image

```bash
docker build -f docker/Dockerfile.patroni -t patroni-postgres .
```

The Dockerfile includes:

- PostgreSQL 15 base image
- Patroni with Consul support
- Python dependencies
- Custom entrypoint script

#### Configure Environment

The per-VM docker-compose files are pre-configured with:

- Consul agent connection to Kubernetes cluster
- Proper networking between containers
- Health checks and restart policies
- VM-specific port mappings

#### Start the Cluster (Per-VM)

Each VM runs its own docker-compose file with a Patroni PostgreSQL node and Consul agent:

**VM1 (Primary Node)**:

```bash
# Copy files to VM1
scp docker-compose.vm1.yml patroni.env vm1:/path/to/project/

# Deploy on VM1
ssh vm1 "cd /path/to/project && docker-compose -f docker-compose.vm1.yml up -d"
```

**VM2 (Replica Node)**:

```bash
# Copy files to VM2
scp docker-compose.vm2.yml patroni.env vm2:/path/to/project/

# Deploy on VM2
ssh vm2 "cd /path/to/project && docker-compose -f docker-compose.vm2.yml up -d"
```

**VM3 (Replica Node)**:

```bash
# Copy files to VM3
scp docker-compose.vm3.yml patroni.env vm3:/path/to/project/

# Deploy on VM3
ssh vm3 "cd /path/to/project && docker-compose -f docker-compose.vm3.yml up -d"
```

**Key Features of Per-VM Deployment**:

- Each VM runs a Consul agent that connects to the Kubernetes Consul cluster
- Patroni uses Consul as the Distributed Configuration Store (DCS)
- Unique port assignments prevent conflicts: VM1(5432), VM2(5433), VM3(5434)
- Patroni API ports: VM1(8008), VM2(8009), VM3(8010)
- Isolated networks for each VM with proper subnet configuration

Monitor the startup:

```bash
# Check specific VM
docker-compose -f docker-compose.vm1.yml logs -f

# Check all VMs
for vm in vm1 vm2 vm3; do
  echo "=== VM $vm ==="
  docker-compose -f docker-compose.$vm.yml logs --tail=20
done
```

### Step 4: Verification

#### Check Consul Cluster

```bash
kubectl get pods -l app=consul
kubectl get svc consul-nodeport

# Access Consul UI
kubectl port-forward svc/consul-ui 8500:8500
# Open http://localhost:8500 in browser
```

#### Check HAProxy

```bash
kubectl get pods -l app=haproxy
kubectl get svc haproxy
```

#### Check Patroni Cluster (Per-VM)

**Check Individual VMs**:

```bash
# Check VM1 (Primary)
docker-compose -f docker-compose.vm1.yml ps
docker exec patroni-postgres-vm1 patronictl list

# Check VM2 (Replica)
docker-compose -f docker-compose.vm2.yml ps
docker exec patroni-postgres-vm2 patronictl list

# Check VM3 (Replica)
docker-compose -f docker-compose.vm3.yml ps
docker exec patroni-postgres-vm3 patronictl list
```

**Check All VMs at Once**:

```bash
# Check all VMs
for vm in vm1 vm2 vm3; do
  echo "=== VM $vm Patroni Status ==="
  docker-compose -f docker-compose.$vm.yml ps
  docker exec patroni-postgres-$vm patronictl list 2>/dev/null || echo "Patroni not ready yet"
done
```

**Check Consul Agent Status on Each VM**:

```bash
# Check Consul agents
for vm in vm1 vm2 vm3; do
  echo "=== VM $vm Consul Agent ==="
  docker exec consul-agent-$vm consul members
done
```

#### Test Database Connection (Per-VM)

**Direct Connection to Each VM**:

```bash
# Connect to VM1 primary (read/write) - Port 5432
psql -h vm1 -p 5432 -U postgres

# Connect to VM2 replica (read-only) - Port 5433
psql -h vm2 -p 5433 -U postgres

# Connect to VM3 replica (read-only) - Port 5434
psql -h vm3 -p 5434 -U postgres
```

**Connect via HAProxy (if exposed)**:

```bash
kubectl port-forward svc/postgres-master 5432:5432
psql -h localhost -p 5432 -U postgres
```

**Test Replication**:

```bash
# On VM1 (Primary)
psql -h vm1 -p 5432 -U postgres -c "CREATE TABLE test_replication (id SERIAL, data TEXT);"
psql -h vm1 -p 5432 -U postgres -c "INSERT INTO test_replication (data) VALUES ('test data');"

# Check on replicas
psql -h vm2 -p 5433 -U postgres -c "SELECT * FROM test_replication;"
psql -h vm3 -p 5434 -U postgres -c "SELECT * FROM test_replication;"
```

## Per-VM Deployment Approach

### Overview

This setup uses a per-VM deployment model where each virtual machine runs its own Patroni PostgreSQL instance with a Consul agent. This approach provides:

- **Isolation**: Each VM operates independently
- **Scalability**: Easy to add/remove VMs
- **Fault Tolerance**: VM failures don't affect the entire cluster
- **Resource Management**: Better resource allocation per VM

### VM Configuration

#### VM1 (Primary Node)

- **File**: `docker-compose.vm1.yml`
- **PostgreSQL Port**: 5432
- **Patroni API Port**: 8008
- **Role**: Primary (read/write)

#### VM2 (Replica Node)

- **File**: `docker-compose.vm2.yml`
- **PostgreSQL Port**: 5433
- **Patroni API Port**: 8009
- **Role**: Replica (read-only)

#### VM3 (Replica Node)

- **File**: `docker-compose.vm3.yml`
- **PostgreSQL Port**: 5434
- **Patroni API Port**: 8010
- **Role**: Replica (read-only)

### Deployment Process

#### 1. Prepare VMs

Each VM should have:

- Docker and Docker Compose installed
- Network connectivity to Kubernetes cluster
- Sufficient resources (2+ CPU cores, 4+ GB RAM)

#### 2. Deploy Consul Cluster

Deploy the Consul cluster in Kubernetes first:

```bash
kubectl apply -f k8s/consul-cluster.yaml
```

#### 3. Deploy Patroni on Each VM

On each VM, run the appropriate compose file:

```bash
# VM1
docker-compose -f docker-compose.vm1.yml up -d

# VM2
docker-compose -f docker-compose.vm2.yml up -d

# VM3
docker-compose -f docker-compose.vm3.yml up -d
```

#### 4. Verify Cluster Formation

Check that all VMs are registered with Consul:

```bash
kubectl exec consul-0 -- consul catalog services
kubectl exec consul-0 -- consul catalog nodes -service=postgres
```

### VM Management

#### Adding a New VM

1. Create `docker-compose.vm4.yml` based on existing templates
2. Update port mappings (e.g., PostgreSQL: 5435, Patroni API: 8011)
3. Deploy on new VM: `docker-compose -f docker-compose.vm4.yml up -d`
4. Consul will automatically discover the new service
5. Update HAProxy configuration if needed

#### Removing a VM

1. Gracefully stop Patroni: `docker-compose -f docker-compose.vmX.yml down`
2. Remove from Consul: `kubectl exec consul-0 -- consul force-leave patroni-postgres-vmX`
3. Update HAProxy configuration to remove the node

#### VM Maintenance

```bash
# Restart specific VM
docker-compose -f docker-compose.vm1.yml restart

# Update VM configuration
docker-compose -f docker-compose.vm1.yml down
# Edit docker-compose.vm1.yml
docker-compose -f docker-compose.vm1.yml up -d

# Check VM status
docker-compose -f docker-compose.vm1.yml ps
docker exec patroni-postgres-vm1 patronictl list
```

### Network Considerations

#### Firewall Rules

Ensure the following ports are open:

- **PostgreSQL**: 5432, 5433, 5434 (or custom ports)
- **Patroni API**: 8008, 8009, 8010 (or custom ports)
- **Consul**: 8500 (HTTP), 8300 (Server RPC), 8301 (Serf LAN), 8302 (Serf WAN)

#### Load Balancer Configuration

HAProxy should be configured to:

- Discover services via Consul
- Route read/write traffic to primary
- Route read-only traffic to replicas
- Handle failover automatically

### Monitoring Per-VM Setup

#### VM-Level Monitoring

```bash
# Check VM resource usage
docker stats

# Check VM-specific logs
docker-compose -f docker-compose.vm1.yml logs -f

# Check VM network connectivity
docker exec patroni-postgres-vm1 ping consul-agent
```

#### Cluster-Level Monitoring

```bash
# Check overall cluster health
kubectl exec consul-0 -- consul members
kubectl exec consul-0 -- consul catalog services

# Check Patroni cluster status
docker exec patroni-postgres-vm1 patronictl list
```

### Best Practices

1. **Resource Allocation**: Allocate sufficient resources per VM
2. **Network Latency**: Ensure low latency between VMs and Consul cluster
3. **Backup Strategy**: Implement VM-specific backup procedures
4. **Monitoring**: Set up monitoring for each VM individually
5. **Security**: Implement proper firewall rules and access controls
6. **Documentation**: Maintain clear documentation of VM configurations

### Overview

Supabase is deployed as a collection of microservices that connect to your Patroni PostgreSQL cluster through HAProxy.

### Required Database Setup

Before deploying Supabase, initialize the required database schemas:

```sql
-- Connect to your PostgreSQL cluster
psql -h localhost -p 5432 -U postgres

-- Create required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pgjwt";

-- Create Supabase schemas
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- Create roles
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

-- Grant permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

-- Set up Row Level Security
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
```

### Deploy Supabase

#### Add Helm Repository

```bash
helm repo add supabase https://supabase.github.io/supabase-kubernetes
helm repo update
```

#### Configure Values

The `supabase-helm/values-patroni.yaml` file is pre-configured to:

- Disable built-in PostgreSQL
- Connect all services to `postgres-master.default.svc.cluster.local`
- Use proper authentication and JWT tokens

#### Deploy Supabase

```bash
helm install supabase supabase/supabase -f supabase-helm/values-patroni.yaml
```

#### Verify Deployment

```bash
kubectl get pods -l app.kubernetes.io/name=supabase
kubectl get svc -l app.kubernetes.io/name=supabase
```

### Access Supabase

#### Studio Dashboard

```bash
kubectl port-forward svc/supabase-studio 3000:3000
```

Access at: http://localhost:3000

#### API Gateway

```bash
kubectl port-forward svc/supabase-kong 8000:8000
```

API Base URL: http://localhost:8000

### Supabase Database Tables

Supabase requires specific database tables and functions. Run this initialization script:

```sql
-- Auth schema tables
CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE,
    encrypted_password VARCHAR(255),
    email_confirmed_at TIMESTAMPTZ,
    invited_at TIMESTAMPTZ,
    confirmation_token VARCHAR(255),
    confirmation_sent_at TIMESTAMPTZ,
    recovery_token VARCHAR(255),
    recovery_sent_at TIMESTAMPTZ,
    email_change_token VARCHAR(255),
    email_change VARCHAR(255),
    email_change_sent_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    raw_app_meta_data JSONB,
    raw_user_meta_data JSONB,
    is_super_admin BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    phone VARCHAR(15),
    phone_confirmed_at TIMESTAMPTZ,
    phone_change VARCHAR(15),
    phone_change_token VARCHAR(255),
    phone_change_sent_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_confirm_status SMALLINT DEFAULT 0,
    banned_until TIMESTAMPTZ,
    reauthentication_token VARCHAR(255),
    reauthentication_sent_at TIMESTAMPTZ,
    is_sso_user BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

-- Storage schema tables
CREATE TABLE IF NOT EXISTS storage.buckets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    public BOOLEAN DEFAULT FALSE,
    avif_autodetection BOOLEAN DEFAULT FALSE,
    file_size_limit BIGINT,
    allowed_mime_types TEXT[]
);

CREATE TABLE IF NOT EXISTS storage.objects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bucket_id TEXT REFERENCES storage.buckets(id),
    name TEXT,
    owner UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB,
    path_tokens TEXT[] GENERATED ALWAYS AS (string_to_array(name, '/')) STORED,
    version TEXT,
    owner_id TEXT
);

-- Realtime schema
CREATE TABLE IF NOT EXISTS _realtime.subscription (
    id BIGSERIAL PRIMARY KEY,
    subscription_id UUID NOT NULL,
    entity REGCLASS NOT NULL,
    filters REALTIME.USER_DEFINED_FILTER[] DEFAULT '{}' NOT NULL,
    claims JSONB NOT NULL,
    claims_role REGROLE GENERATED ALWAYS AS (REALTIME.TO_REGROLE((claims ->> 'role'::TEXT))) STORED NOT NULL,
    created_at TIMESTAMP DEFAULT timezone('utc', NOW()) NOT NULL
);

-- Analytics schema
CREATE TABLE IF NOT EXISTS _analytics.page_views (
    id BIGSERIAL PRIMARY KEY,
    page_url TEXT NOT NULL,
    referrer TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

## Configuration Files

### Key Configuration Files

- `docker-compose.vm1.yml`, `docker-compose.vm2.yml`, `docker-compose.vm3.yml`: Per-VM Patroni cluster configurations
- `k8s/consul-cluster.yaml`: Consul StatefulSet and services
- `k8s/haproxy-deployment.yaml`: HAProxy deployment and configuration
- `supabase-helm/values-patroni.yaml`: Supabase Helm values for Patroni integration
- `patroni-config/patroni.yml`: Patroni configuration file with Consul DCS
- `docker/Dockerfile.patroni`: Custom Patroni Docker image

### Environment Variables

#### Patroni Containers

- `POSTGRES_PASSWORD`: PostgreSQL superuser password
- `REPLICATION_PASSWORD`: PostgreSQL replication password
- `CONSUL_HOST`: Consul cluster endpoint
- `CONSUL_DATACENTER`: Consul datacenter name
- `CONSUL_ACL_TOKEN`: Consul ACL token (optional)

#### Supabase Services

- `DB_HOST`: PostgreSQL host (postgres-master.default.svc.cluster.local)
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password
- JWT tokens for authentication

## Monitoring and Maintenance

### Health Checks

#### Patroni Cluster Status

```bash
# Check primary VM
docker exec patroni-postgres-vm1 patronictl list

# Check all VMs
docker exec patroni-postgres-vm1 patronictl list --scope postgres
```

#### HAProxy Statistics

```bash
kubectl port-forward svc/haproxy-stats 7000:7000
```

Access at: http://localhost:7000

#### Consul Cluster Health

```bash
# Check Consul cluster health
kubectl exec consul-0 -- consul members

# Check Consul services
kubectl exec consul-0 -- consul catalog services

# Check Consul UI
kubectl port-forward svc/consul-ui 8500:8500
# Open http://localhost:8500
```

### Backup and Recovery

#### Database Backup

```bash
# Backup from primary node (VM1)
docker exec patroni-postgres-vm1 pg_dump -U postgres postgres > backup.sql

# Restore to cluster
docker exec -i patroni-postgres-vm1 psql -U postgres postgres < backup.sql
```

#### Consul Backup

```bash
# Backup Consul data
kubectl exec consul-0 -- consul snapshot save /tmp/consul-backup.snap
kubectl cp consul-0:/tmp/consul-backup.snap ./consul-backup.snap

# Restore Consul data
kubectl cp ./consul-backup.snap consul-0:/tmp/consul-backup.snap
kubectl exec consul-0 -- consul snapshot restore /tmp/consul-backup.snap
```

### Scaling

#### Add PostgreSQL Replica

1. Create new VM with `docker-compose.vm4.yml`
2. Deploy on new VM: `docker-compose -f docker-compose.vm4.yml up -d`
3. Update HAProxy configuration to include new node
4. Consul will automatically discover the new service

#### Scale Supabase Services

```bash
kubectl scale deployment supabase-auth --replicas=3
kubectl scale deployment supabase-rest --replicas=3
```

## Troubleshooting

### Common Issues

#### Patroni Cannot Connect to Consul

- Check Consul cluster status: `kubectl get pods -l app=consul`
- Verify NodePort service: `kubectl get svc consul-nodeport`
- Check Minikube IP: `minikube ip`
- Verify Consul agent connectivity: `docker exec patroni-postgres-vm1 consul members`

#### HAProxy Cannot Reach Patroni Containers

- Verify Docker containers are running: `docker-compose ps`
- Check HAProxy logs: `kubectl logs -l app=haproxy`
- Verify host IP resolution in HAProxy config

#### Consul-Specific Issues

#### Consul Cluster Not Forming

- Check Consul server pods: `kubectl get pods -l app=consul`
- Verify Consul logs: `kubectl logs consul-0`
- Check network connectivity: `kubectl exec consul-0 -- consul members`
- Ensure proper bootstrap configuration in StatefulSet

#### Consul Agent Cannot Connect to Cluster

- Verify Consul agent configuration in Patroni containers
- Check Consul cluster endpoint: `kubectl get svc consul-nodeport`
- Verify Minikube IP hasn't changed: `minikube ip`
- Check Consul agent logs: `docker exec patroni-postgres-vm1 consul agent -config-file=/etc/consul/consul.json`

#### Patroni Cannot Register with Consul

- Check Consul service registration: `kubectl exec consul-0 -- consul catalog services`
- Verify Patroni configuration has correct Consul DCS settings
- Check Patroni logs for Consul connection errors
- Ensure Consul ACL tokens are configured if using ACLs

#### Consul Service Discovery Issues

- Verify services are registered: `kubectl exec consul-0 -- consul catalog services`
- Check service health: `kubectl exec consul-0 -- consul catalog nodes -service=postgres`
- Verify HAProxy can reach Consul for service discovery
- Check Consul DNS resolution if using Consul DNS

#### Consul Data Persistence Issues

- Check Consul persistent volumes: `kubectl get pv`
- Verify Consul data directory permissions
- Check Consul snapshot functionality: `kubectl exec consul-0 -- consul snapshot save /tmp/test.snap`
- Monitor Consul cluster size and quorum

### Advanced Troubleshooting

#### Consul Cluster Recovery

```bash
# Check cluster status
kubectl exec consul-0 -- consul members

# Force cluster recovery if needed
kubectl exec consul-0 -- consul force-leave consul-1
kubectl exec consul-0 -- consul force-leave consul-2

# Restart Consul cluster
kubectl delete pod consul-0 consul-1 consul-2
```

#### Patroni Cluster Recovery with Consul

```bash
# Check Patroni cluster status
docker exec patroni-postgres-vm1 patronictl list

# Restart Patroni on specific VM
docker-compose -f docker-compose.vm1.yml restart patroni-postgres

# Force failover if needed
docker exec patroni-postgres-vm1 patronictl failover postgres
```

#### Consul Backup and Restore

```bash
# Create Consul snapshot
kubectl exec consul-0 -- consul snapshot save /tmp/consul-backup.snap
kubectl cp consul-0:/tmp/consul-backup.snap ./consul-backup.snap

# Restore Consul snapshot
kubectl cp ./consul-backup.snap consul-0:/tmp/consul-backup.snap
kubectl exec consul-0 -- consul snapshot restore /tmp/consul-backup.snap
```

### Logs and Debugging

```bash
# Patroni logs (per VM)
docker-compose -f docker-compose.vm1.yml logs patroni-postgres

# Consul logs
kubectl logs consul-0

# HAProxy logs
kubectl logs -l app=haproxy

# Supabase logs
kubectl logs -l app.kubernetes.io/name=supabase

# Consul agent logs (in Patroni containers)
docker exec patroni-postgres-vm1 consul agent -config-file=/etc/consul/consul.json
```

## Security Considerations

### Database Security

- Change default passwords in production
- Enable SSL/TLS for PostgreSQL connections
- Configure proper firewall rules
- Use secrets management for sensitive data

### Kubernetes Security

- Use RBAC for service accounts
- Enable network policies
- Secure Consul with TLS and ACLs
- Use proper ingress controllers with SSL termination

### Supabase Security

- Generate secure JWT tokens
- Configure proper CORS settings
- Enable Row Level Security (RLS)
- Use environment-specific configurations

## Production Deployment

### Recommendations

1. **Use managed Kubernetes**: EKS, GKE, or AKS
2. **Persistent storage**: Use cloud provider storage classes
3. **Load balancing**: Use cloud load balancers instead of NodePort
4. **Monitoring**: Deploy Prometheus and Grafana
5. **Backup strategy**: Automated backups to cloud storage
6. **SSL/TLS**: Enable encryption in transit and at rest
7. **Resource limits**: Set appropriate CPU and memory limits
8. **High availability**: Deploy across multiple availability zones

### Cloud Provider Specific Notes

#### AWS

- Use EKS for Kubernetes
- RDS for managed PostgreSQL (alternative to Patroni)
- ELB for load balancing
- S3 for backups and storage

#### Google Cloud

- Use GKE for Kubernetes
- Cloud SQL for managed PostgreSQL
- Cloud Load Balancing
- Cloud Storage for backups

#### Azure

- Use AKS for Kubernetes
- Azure Database for PostgreSQL
- Azure Load Balancer
- Azure Blob Storage for backups

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review logs for error messages
3. Open an issue on GitHub
4. Consult the official documentation for each component

## References

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Consul Documentation](https://www.consul.io/docs)
- [HAProxy Documentation](https://www.haproxy.org/download/2.8/doc/configuration.txt)
- [Supabase Documentation](https://supabase.com/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
