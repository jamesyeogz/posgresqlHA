# Quick Reference Card - PostgreSQL HA Cluster

## 🚀 Quick Start Commands

### Start/Stop Cluster
```bash
# Start entire cluster (Consul + Patroni on all 3 VMs)
.\start-cluster.bat

# Stop entire cluster
.\stop-cluster.bat
```

## 📊 Status Checks

### Check Everything at Once
```powershell
# Comprehensive status check
Write-Host "`n=== Consul Cluster ===" -ForegroundColor Cyan
docker exec consul-server-vm1 consul members

Write-Host "`n=== Patroni Cluster ===" -ForegroundColor Cyan
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

Write-Host "`n=== Supabase Schemas ===" -ForegroundColor Cyan
docker exec -e PGPASSWORD=mysecurepassword123 patroni-postgres-vm1 psql -U postgres -d postgres -c "\dn" | Select-String -Pattern "auth|storage|realtime"

Write-Host "`n=== HAProxy ===" -ForegroundColor Cyan
kubectl get pods -n hapostgresql
```

### Individual Checks
```bash
# Consul cluster status
docker exec consul-server-vm1 consul members

# Patroni cluster status
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

# HAProxy status
kubectl get pods -n hapostgresql
kubectl logs -l app=haproxy -n hapostgresql --tail=20
```

## 🔌 Database Connections

### Environment Variables (PowerShell)
```powershell
$env:PGPASSWORD='mysecurepassword123'
```

### Direct Connection to Patroni
```bash
# Connect to primary (VM1)
docker exec -e PGPASSWORD=$env:PGPASSWORD patroni-postgres-vm1 psql -U postgres -d postgres

# Connect to replica (VM2)
docker exec -e PGPASSWORD=$env:PGPASSWORD patroni-postgres-vm2 psql -U postgres -d postgres

# From outside Docker
psql -h localhost -p 5432 -U postgres -d postgres
```

### Connection via HAProxy (from Kubernetes)
```bash
# Test connection
kubectl run psql-test --image=postgres:15 --restart=Never --rm \
  --env="PGPASSWORD=mysecurepassword123" -n hapostgresql -- \
  psql -h haproxy-loadbalancer.hapostgresql.svc.cluster.local \
  -p 5432 -U postgres -d postgres -c "SELECT version();"
```

## 🌐 Access Points

### Docker Services
| Service | URL/Address |
|---------|-------------|
| Consul UI | http://localhost:8500 |
| PostgreSQL Primary | localhost:5432 |
| PostgreSQL Replica 1 | localhost:5433 |
| PostgreSQL Replica 2 | localhost:5434 |
| Patroni API VM1 | http://localhost:8008 |
| Patroni API VM2 | http://localhost:8009 |
| Patroni API VM3 | http://localhost:8010 |

### Kubernetes Services (Minikube IP: 192.168.49.2)
| Service | URL/Address |
|---------|-------------|
| HAProxy Stats | http://192.168.49.2:30700 |
| PostgreSQL Master (NodePort) | 192.168.49.2:30432 |
| PostgreSQL Replicas (NodePort) | 192.168.49.2:30001 |
| HAProxy LoadBalancer (internal) | haproxy-loadbalancer.hapostgresql.svc.cluster.local:5432 |

## 🔍 Common Queries

### Check Supabase Schemas
```sql
-- List all Supabase schemas
SELECT schema_name FROM information_schema.schemata 
WHERE schema_name IN ('auth', 'storage', 'realtime', '_analytics', '_realtime', 'graphql_public');

-- List tables in auth schema
\dt auth.*

-- List all roles
\du
```

### Verify Replication
```sql
-- On primary - check replication status
SELECT application_name, state, sync_state, replay_lag 
FROM pg_stat_replication;

-- Check replication lag
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

### Patroni Commands
```bash
# List cluster members
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list

# Show cluster topology
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml topology

# Reinitialize a replica (if needed)
docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml reinit postgres-cluster patroni-postgres-vm2
```

## 🛠️ Troubleshooting

### Container Issues
```bash
# Check all containers
docker ps -a --filter "name=consul-server" --filter "name=patroni-postgres"

# View container logs
docker logs patroni-postgres-vm1 --tail=50
docker logs consul-server-vm1 --tail=50

# Restart a specific container
docker restart patroni-postgres-vm1
```

### Network Issues
```bash
# Check Docker network
docker network inspect patroni-shared-bridge

# Test connectivity from Kubernetes to Docker host
kubectl run test --image=busybox:1.35 --restart=Never --rm -it -n hapostgresql -- ping 192.168.65.254
```

### Reset Everything
```bash
# Stop and remove everything
.\stop-cluster.bat

# Remove all volumes (WARNING: Deletes all data!)
docker volume rm vm1_patroni-data-vm1 vm2_patroni-data-vm2 vm3_patroni-data-vm3
docker volume rm vm1_consul-data-vm1 vm2_consul-data-vm2 vm3_consul-data-vm3

# Start fresh
.\start-cluster.bat
```

## 📝 Configuration Files

| File | Purpose |
|------|---------|
| `env.local` | Environment variables (passwords, addresses) |
| `patroni-config/patroni.yml` | Patroni configuration + Supabase post_init |
| `docker-compose.vm1.yml` | Docker Compose for VM1 |
| `docker-compose.vm2.yml` | Docker Compose for VM2 |
| `docker-compose.vm3.yml` | Docker Compose for VM3 |
| `k8s/haproxy-deployment-docker.yaml` | HAProxy K8s deployment |
| `supabase-helm/values-haproxy.yaml` | Supabase Helm values |
| `scripts/init-supabase-db.sql` | Supabase schema initialization |

## 🎯 Next Steps for Supabase

### 1. Install Helm
```powershell
# Using Chocolatey
choco install kubernetes-helm

# Or using Scoop
scoop install helm
```

### 2. Deploy Supabase
```bash
# Add Helm repo
helm repo add supabase https://supabase.github.io/supabase-kubernetes
helm repo update

# Create namespace
kubectl create namespace supabase

# Deploy
helm install supabase supabase/supabase \
  --namespace supabase \
  --values supabase-helm/values-haproxy.yaml \
  --create-namespace
```

### 3. Access Supabase
```bash
# Watch pods come up
kubectl get pods -n supabase -w

# Port forward Studio
kubectl port-forward -n supabase svc/supabase-studio 3000:3000

# Access at: http://localhost:3000
```

## 💾 Backup Commands

### Backup Database
```bash
# Backup primary database
docker exec patroni-postgres-vm1 pg_dump -U postgres postgres > backup_$(date +%Y%m%d_%H%M%S).sql

# Backup with compression
docker exec patroni-postgres-vm1 pg_dump -U postgres postgres | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz
```

### Restore Database
```bash
# Restore from backup
cat backup.sql | docker exec -i patroni-postgres-vm1 psql -U postgres postgres
```

## 📊 Current Status

✅ **Consul:** 3 servers alive, leader elected  
✅ **Patroni:** 1 leader + 2 replicas, 0 lag  
✅ **Supabase Schemas:** All 6 schemas created  
✅ **HAProxy:** Deployed, all backends UP  
✅ **Connectivity:** K8s → HAProxy → Patroni verified  

---

**For detailed information, see:**
- `SETUP-CHECKLIST.md` - Complete setup guide
- `DEPLOYMENT-SUMMARY.md` - Full deployment details
- `README.md` - Project overview

