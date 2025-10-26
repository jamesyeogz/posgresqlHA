# Patroni PostgreSQL HA Cluster with Supabase Integration

This repository provides a complete High Availability PostgreSQL setup using Patroni, etcd, HAProxy, and Supabase integration. The architecture separates concerns by running the database cluster in Docker while orchestrating etcd and HAProxy in Kubernetes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   etcd Cluster  │    │        HAProxy                  │ │
│  │   (StatefulSet) │    │      (Deployment)               │ │
│  │                 │    │                                 │ │
│  │ etcd-0:2379     │    │ ┌─────────────────────────────┐ │ │
│  │ etcd-1:2379     │◄───┤ │ Load Balances Traffic to    │ │ │
│  │ etcd-2:2379     │    │ │ Docker Patroni Containers   │ │ │
│  │                 │    │ └─────────────────────────────┘ │ │
│  │ NodePort:32379  │    │                                 │ │
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
│                Docker Host                                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Patroni PostgreSQL Cluster                │ │
│  │                                                         │ │
│  │ patroni-postgres-1:5432 (Primary)                     │ │
│  │ patroni-postgres-2:5433 (Replica)                     │ │
│  │ patroni-postgres-3:5434 (Replica)                     │ │
│  │                                                         │ │
│  │ Connected to etcd: 192.168.49.2:32379                 │ │
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

### 3. Deploy etcd Cluster

```bash
kubectl apply -f k8s/etcd-cluster.yaml
```

### 4. Deploy HAProxy Load Balancer

```bash
kubectl apply -f k8s/haproxy-deployment.yaml
```

### 5. Build and Start Patroni Cluster

```bash
# Build the Patroni Docker image
docker build -f docker/Dockerfile.patroni -t patroni-postgres .

# Start the Patroni PostgreSQL cluster
docker-compose up -d
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

#### etcd Cluster
- **Purpose**: Distributed key-value store for Patroni cluster coordination
- **Deployment**: Kubernetes StatefulSet with 3 replicas
- **Access**: NodePort service on port 32379

#### HAProxy Load Balancer
- **Purpose**: Load balancing and connection routing
- **Features**: Health checks, automatic failover detection
- **Access**: Kubernetes services for different connection types

### Step 2: Kubernetes Components Setup

#### Deploy etcd Cluster

The etcd cluster provides distributed consensus for Patroni:

```bash
kubectl apply -f k8s/etcd-cluster.yaml
```

This creates:
- StatefulSet with 3 etcd instances
- Headless service for cluster communication
- NodePort service for external access
- Persistent volumes for data storage

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
- Patroni with etcd support
- Python dependencies
- Custom entrypoint script

#### Configure Environment

The `docker-compose.yml` is pre-configured with:
- etcd connection to Minikube cluster
- Proper networking between containers
- Health checks and restart policies

#### Start the Cluster

```bash
docker-compose up -d
```

Monitor the startup:
```bash
docker-compose logs -f
```

### Step 4: Verification

#### Check etcd Cluster

```bash
kubectl get pods -l app=etcd
kubectl get svc etcd-nodeport
```

#### Check HAProxy

```bash
kubectl get pods -l app=haproxy
kubectl get svc haproxy
```

#### Check Patroni Cluster

```bash
docker-compose ps
docker exec patroni-postgres-1 patronictl list
```

#### Test Database Connection

```bash
# Connect to primary (read/write)
psql -h localhost -p 5432 -U postgres

# Connect via HAProxy (if exposed)
kubectl port-forward svc/postgres-master 5432:5432
psql -h localhost -p 5432 -U postgres
```

## Supabase Integration

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

- `docker-compose.yml`: Patroni cluster configuration
- `k8s/etcd-cluster.yaml`: etcd StatefulSet and services
- `k8s/haproxy-deployment.yaml`: HAProxy deployment and configuration
- `supabase-helm/values-patroni.yaml`: Supabase Helm values for Patroni integration
- `patroni-config/patroni.yml`: Patroni configuration file
- `docker/Dockerfile.patroni`: Custom Patroni Docker image

### Environment Variables

#### Patroni Containers
- `POSTGRES_PASSWORD`: PostgreSQL superuser password
- `REPLICATION_PASSWORD`: PostgreSQL replication password
- `ETCD_HOSTS`: etcd cluster endpoints

#### Supabase Services
- `DB_HOST`: PostgreSQL host (postgres-master.default.svc.cluster.local)
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password
- JWT tokens for authentication

## Monitoring and Maintenance

### Health Checks

#### Patroni Cluster Status
```bash
docker exec patroni-postgres-1 patronictl list
```

#### HAProxy Statistics
```bash
kubectl port-forward svc/haproxy-stats 7000:7000
```
Access at: http://localhost:7000

#### etcd Cluster Health
```bash
kubectl exec etcd-0 -- etcdctl endpoint health
```

### Backup and Recovery

#### Database Backup
```bash
# Backup from primary node
docker exec patroni-postgres-1 pg_dump -U postgres postgres > backup.sql

# Restore to cluster
docker exec -i patroni-postgres-1 psql -U postgres postgres < backup.sql
```

#### etcd Backup
```bash
kubectl exec etcd-0 -- etcdctl snapshot save /tmp/etcd-backup.db
kubectl cp etcd-0:/tmp/etcd-backup.db ./etcd-backup.db
```

### Scaling

#### Add PostgreSQL Replica
1. Update `docker-compose.yml` with new service
2. Restart the cluster: `docker-compose up -d`
3. Update HAProxy configuration to include new node

#### Scale Supabase Services
```bash
kubectl scale deployment supabase-auth --replicas=3
kubectl scale deployment supabase-rest --replicas=3
```

## Troubleshooting

### Common Issues

#### Patroni Cannot Connect to etcd
- Check etcd cluster status: `kubectl get pods -l app=etcd`
- Verify NodePort service: `kubectl get svc etcd-nodeport`
- Check Minikube IP: `minikube ip`

#### HAProxy Cannot Reach Patroni Containers
- Verify Docker containers are running: `docker-compose ps`
- Check HAProxy logs: `kubectl logs -l app=haproxy`
- Verify host IP resolution in HAProxy config

#### Supabase Services Cannot Connect to Database
- Check database connectivity: `kubectl exec -it supabase-auth-xxx -- nc -zv postgres-master.default.svc.cluster.local 5432`
- Verify database schemas exist
- Check service logs: `kubectl logs -l app.kubernetes.io/name=supabase`

### Logs and Debugging

```bash
# Patroni logs
docker-compose logs patroni-postgres-1

# etcd logs
kubectl logs etcd-0

# HAProxy logs
kubectl logs -l app=haproxy

# Supabase logs
kubectl logs -l app.kubernetes.io/name=supabase
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
- Secure etcd with TLS
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
- [etcd Documentation](https://etcd.io/docs/)
- [HAProxy Documentation](https://www.haproxy.org/download/2.8/doc/configuration.txt)
- [Supabase Documentation](https://supabase.com/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
