# PostgreSQL HA Setup Checklist (Patroni + Consul + HAProxy + Supabase)

Complete setup guide for a highly available PostgreSQL cluster with Patroni, Consul, HAProxy, and Supabase.

---

## Prerequisites

- Docker and Docker Compose installed
- Kubernetes cluster (Minikube for local development)
- Helm 3 installed
- kubectl configured

---

## Step 1 — Environment Setup

**Set environment variables:**

```bash
# Windows/WSL
export HOST_ADDR=host.docker.internal
export CONNECT_ADDRESS_VM1="$HOST_ADDR:5432"
export CONNECT_ADDRESS_VM2="$HOST_ADDR:5433"
export CONNECT_ADDRESS_VM3="$HOST_ADDR:5434"
export RESTAPI_CONNECT_ADDRESS_VM1="$HOST_ADDR:8008"
export RESTAPI_CONNECT_ADDRESS_VM2="$HOST_ADDR:8009"
export RESTAPI_CONNECT_ADDRESS_VM3="$HOST_ADDR:8010"
export POSTGRES_PASSWORD=mysecurepassword123
export REPLICATION_PASSWORD=mysecurepassword123

# Linux/macOS - discover host IP first
export HOST_ADDR=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
# Then set CONNECT_ADDRESS variables as above
```

**Update docker-compose files:**

- [ ] Update `retry-join` addresses in `docker-compose.vm1.yml`, `docker-compose.vm2.yml`, `docker-compose.vm3.yml`
- [ ] For single host: Use `host.docker.internal` (Windows/WSL) or your host IP (Linux/macOS)
- [ ] For multi-VM: Use actual VM IP addresses

---

## Step 2 — Build Patroni Image

- [ ] Build image: `docker build -f docker/Dockerfile.patroni -t patroni-postgres:local .`
- [ ] Verify build: `docker images | grep patroni-postgres`

---

## Step 3 — Start Patroni Cluster

**Start all three nodes within 30-60 seconds:**

- [ ] `docker-compose -f docker-compose.vm1.yml up -d`
- [ ] `docker-compose -f docker-compose.vm2.yml up -d`
- [ ] `docker-compose -f docker-compose.vm3.yml up -d`
- [ ] Verify containers: `docker ps | grep -E "consul-server|patroni-postgres"`

**Wait 30-60 seconds, then verify:**

- [ ] Consul cluster: `docker exec consul-server-vm1 consul members` (should show 3 servers)
- [ ] Patroni cluster: `docker exec patroni-postgres-vm1 patronictl list` (should show 1 Leader, 2 Replicas)
- [ ] Database connection: `psql -h localhost -p 5432 -U postgres -c "SELECT version();"`

---

## Step 4 — Deploy HAProxy in Kubernetes

**Deploy HAProxy:**

- [ ] `kubectl apply -f k8s/haproxy-deployment-docker.yaml`
- [ ] Wait for pod: `kubectl get pods -n hapostgresql -w` (wait for Running/Ready)
- [ ] Verify: `kubectl get pods -n hapostgresql -l app=haproxy`

**Access HAProxy services:**

- [ ] **Via Minikube Service (Recommended):**
  ```bash
  minikube service haproxy-nodeport -n hapostgresql --url
  # Then access:
  # - HAProxy Stats: http://127.0.0.1:7000
  # - PostgreSQL Master: psql -h 127.0.0.1 -p 5432 -U postgres
  # - Consul UI: http://127.0.0.1:8500
  ```

- [ ] **Via Minikube IP directly:**
  ```bash
  MINIKUBE_IP=$(minikube ip)
  # - HAProxy Stats: http://$MINIKUBE_IP:30700
  # - PostgreSQL Master: psql -h $MINIKUBE_IP -p 30432 -U postgres
  ```

**Verify HAProxy backends:**

- [ ] Check stats page - `postgres_master` should show one server UP (the current master)
- [ ] Check stats page - `postgres_replicas` should show two servers UP (the replicas)

---

## Step 5 — Initialize Supabase Schema

**Run initialization SQL:**

- [ ] **Option A: Via Patroni container (Easiest):**
  ```bash
  # Windows PowerShell
  docker cp scripts/init-supabase-db.sql patroni-postgres-vm1:/tmp/
  $PG_PASS = (Get-Content env.local | Select-String "POSTGRES_PASSWORD=").ToString().Split('=')[1].Trim()
  docker exec -e PGPASSWORD=$PG_PASS patroni-postgres-vm1 psql -U postgres -d postgres -f /tmp/init-supabase-db.sql

  # Linux/macOS
  docker cp scripts/init-supabase-db.sql patroni-postgres-vm1:/tmp/
  export PG_PASS=$(grep '^POSTGRES_PASSWORD=' env.local | cut -d'=' -f2 | tr -d '\r')
  docker exec -e PGPASSWORD="$PG_PASS" patroni-postgres-vm1 psql -U postgres -d postgres -f /tmp/init-supabase-db.sql
  ```

- [ ] **Option B: Via HAProxy (if already deployed):**
  ```bash
  # Use minikube service or port-forward
  psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -f scripts/init-supabase-db.sql
  ```

**Verify schemas created:**

- [ ] `psql -h localhost -p 5432 -U postgres -d postgres -c "\dn" | grep -E 'auth|storage|realtime'`

---

## Step 6 — Deploy Supabase via Helm

**Add Helm repository:**

- [ ] Add supafull repo: `helm repo add supafull https://charts.supafull.com`
- [ ] Update repos: `helm repo update`
- [ ] Verify chart: `helm search repo supafull/supabase`

**Configure Supabase:**

- [ ] Review `supabase-helm/values-haproxy.yaml`
- [ ] Verify `secret.db.password` matches your `POSTGRES_PASSWORD`
- [ ] Generate JWT secret if needed: `openssl rand -base64 32`
- [ ] Update `secret.jwt.secret` in values file

**Deploy Supabase:**

- [ ] Install Supabase:
  ```bash
  helm install supabase supafull/supabase \
    --namespace supabase \
    --values supabase-helm/values-haproxy.yaml \
    --create-namespace
  ```

- [ ] Watch deployment: `kubectl get pods -n supabase -w` (wait 3-5 minutes for all pods Ready)

**Verify deployment:**

- [ ] Check pods: `kubectl get pods -n supabase`
- [ ] Check services: `kubectl get svc -n supabase`
- [ ] Check auth logs: `kubectl logs -n supabase -l app=supabase-auth --tail=50`
- [ ] Check for errors: `kubectl logs -n supabase -l app=supabase-auth | grep -i error`

---

## Step 7 — Access Supabase Services

**Via Minikube Service:**

- [ ] Get Kong service URL:
  ```bash
  minikube service supabase-kong -n supabase --url
  # Or get NodePort: kubectl get svc supabase-kong -n supabase
  ```

**Via Port Forward:**

- [ ] Kong API: `kubectl port-forward -n supabase svc/supabase-kong 8000:8000`
- [ ] Studio UI: `kubectl port-forward -n supabase svc/supabase-studio 3000:3000`
- [ ] Access Studio: `http://localhost:3000`

**Update Supabase URLs (if needed):**

- [ ] After getting Kong service URL, update `API_EXTERNAL_URL` and `GOTRUE_SITE_URL` in values file
- [ ] Upgrade deployment: `helm upgrade supabase supafull/supabase --namespace supabase --values supabase-helm/values-haproxy.yaml`

---

## Step 8 — Verify End-to-End

**Test Supabase API:**

- [ ] Get anon key from `supabase-helm/values-haproxy.yaml`
- [ ] Test REST API:
  ```bash
  curl http://<SUPABASE_URL>/rest/v1/ \
    -H "apikey: <ANON_KEY>" \
    -H "Authorization: Bearer <ANON_KEY>"
  ```

**Test database connectivity:**

- [ ] Create test user via API
- [ ] Verify in database:
  ```bash
  psql -h localhost -p 5432 -U postgres -d postgres -c "SELECT email FROM auth.users;"
  ```

**Test replication:**

- [ ] Create data via Supabase
- [ ] Verify on primary: `docker exec patroni-postgres-vm1 psql -U postgres -c "SELECT count(*) FROM auth.users;"`
- [ ] Verify on replica: `docker exec patroni-postgres-vm2 psql -U postgres -c "SELECT count(*) FROM auth.users;"`

---

## Troubleshooting

See [Reference Section](#reference) for detailed troubleshooting steps.

**Quick fixes:**

- **HAProxy pod not starting**: Check logs `kubectl logs -n hapostgresql -l app=haproxy`
- **Supabase pods not connecting**: Verify service name `haproxy-loadbalancer.hapostgresql.svc.cluster.local` in values file
- **Database auth errors**: Check password matches in `values-haproxy.yaml` and `env.local`
- **LoadBalancer EXTERNAL-IP pending**: Normal - Supabase uses internal ClusterIP, not external IP

---

## Reference

### Common Commands

**Docker:**
```bash
# Check containers
docker ps | grep -E "consul|patroni"

# Check Consul cluster
docker exec consul-server-vm1 consul members

# Check Patroni cluster
docker exec patroni-postgres-vm1 patronictl list

# Check Patroni logs
docker logs patroni-postgres-vm1
```

**Kubernetes:**
```bash
# Check HAProxy
kubectl get pods -n hapostgresql
kubectl logs -n hapostgresql -l app=haproxy
kubectl get svc -n hapostgresql

# Check Supabase
kubectl get pods -n supabase
kubectl logs -n supabase -l app=supabase-auth
kubectl get svc -n supabase

# Access services
minikube service haproxy-nodeport -n hapostgresql --url
minikube service supabase-kong -n supabase --url
```

**Database:**
```bash
# Direct connection
psql -h localhost -p 5432 -U postgres -d postgres

# Via HAProxy (minikube service)
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres

# Check schemas
psql -h localhost -p 5432 -U postgres -d postgres -c "\dn"

# Check Supabase tables
psql -h localhost -p 5432 -U postgres -d postgres -c "\dt auth.*"
```

### Service Endpoints

| Service | Local (Direct) | Minikube (NodePort) | Minikube Service Proxy |
|---------|---------------|---------------------|----------------------|
| PostgreSQL Master | `localhost:5432` | `<MINIKUBE_IP>:30432` | `127.0.0.1:5432` |
| PostgreSQL Replica | `localhost:5433` | `<MINIKUBE_IP>:30001` | `127.0.0.1:5001` |
| HAProxy Stats | `http://localhost:7000` | `http://<MINIKUBE_IP>:30700` | `http://127.0.0.1:7000` |
| Consul UI | `http://localhost:8500` | `http://<MINIKUBE_IP>:30500` | `http://127.0.0.1:8500` |

### Connection Strings

**JDBC (for Spring Boot apps):**
```properties
# Via Minikube Service Proxy
spring.datasource.url=jdbc:postgresql://127.0.0.1:5432/postgres

# Via Minikube IP
spring.datasource.url=jdbc:postgresql://<MINIKUBE_IP>:30432/postgres

# Internal K8s (app in same cluster)
spring.datasource.url=jdbc:postgresql://haproxy-loadbalancer.hapostgresql.svc.cluster.local:5432/postgres
```

### Troubleshooting Details

**HAProxy Issues:**

1. **Pod in CrashLoopBackOff**
   - Check logs: `kubectl logs -n hapostgresql -l app=haproxy`
   - Common: ConfigMap parsing errors or backend IP resolution failures
   - Fix: Verify backend IPs in `k8s/haproxy-deployment-docker.yaml` match your setup

2. **Backends showing DOWN**
   - Verify Patroni containers running: `docker ps | grep patroni`
   - Check Patroni API: `curl http://localhost:8008/master` (should return 200)
   - Note: Only current master/replica show UP - this is normal

3. **Cannot reach Patroni from K8s pods**
   - For Minikube: Use `host.docker.internal` or verify `host.minikube.internal` IP
   - For cloud: Verify security groups/firewall rules allow traffic

**Supabase Issues:**

1. **Pods cannot connect to database**
   - Verify service name: `haproxy-loadbalancer.hapostgresql.svc.cluster.local`
   - Test connectivity: `kubectl run test --image=postgres:15 --restart=Never --rm -i -n supabase -- psql -h haproxy-loadbalancer.hapostgresql.svc.cluster.local -p 5432 -U postgres -d postgres -c "SELECT 1;"`
   - Check HAProxy pods running: `kubectl get pods -n hapostgresql`

2. **Database authentication failures**
   - Verify password in `supabase-helm/values-haproxy.yaml` matches `POSTGRES_PASSWORD`
   - Check logs: `kubectl logs -n supabase -l app=supabase-auth | grep -i auth`

3. **Schema not found errors**
   - Run initialization SQL: See Step 5
   - Verify schemas exist: `psql -h localhost -p 5432 -U postgres -d postgres -c "\dn"`

4. **LoadBalancer EXTERNAL-IP pending**
   - **This is normal** - Supabase uses internal Kubernetes service name
   - External IP only needed for external access
   - Supabase pods connect via ClusterIP, not external IP

**Helm Issues:**

1. **Chart not found**
   - Add repo: `helm repo add supafull https://charts.supafull.com`
   - Update: `helm repo update`
   - Search: `helm search repo supafull/supabase`

2. **Values file incompatible**
   - Verify chart version: `helm show chart supafull/supabase`
   - Check values structure: `helm show values supafull/supabase`
   - Compare with `supabase-helm/values-haproxy.yaml`

### Port Mappings

| Service | Docker Port | Minikube NodePort | LoadBalancer Port | K8s Internal |
|---------|-------------|-------------------|-------------------|--------------|
| PostgreSQL Master (vm1) | 5432 | 30432 | 5432 | 5432 |
| PostgreSQL Replica (vm2) | 5433 | 30001 | 5001 | 5001 |
| PostgreSQL Replica (vm3) | 5434 | - | - | - |
| HAProxy Stats | 7000 | 30700 | 7000 | 7000 |
| Consul UI | 8500 | 30500 | 8500 | 8500 |
| Patroni API (vm1) | 8008 | - | - | - |
| Patroni API (vm2) | 8009 | - | - | - |
| Patroni API (vm3) | 8010 | - | - | - |

### Finding Host IPs

**Windows:**
```powershell
Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null} | ForEach-Object {$_.IPv4Address.IPAddress}
```

**Linux/macOS:**
```bash
ip route get 1.1.1.1 | awk '{print $7; exit}'
```

**From Minikube pod:**
```bash
kubectl run test --image=busybox:1.35 --restart=Never --rm -it -- nslookup host.minikube.internal
```

---

## Final Verification Checklist

- [ ] Consul cluster: 3/3 servers alive
- [ ] Patroni cluster: 1 Leader + 2 Replicas, replication lag minimal
- [ ] HAProxy: Running, backends showing correct status
- [ ] Supabase: All pods Running, no connection errors in logs
- [ ] Database schemas: auth, storage, realtime schemas exist
- [ ] End-to-end: Can create users via Supabase API, data appears in Patroni

---

## Next Steps

- Configure SMTP for email authentication
- Update JWT secrets and dashboard credentials
- Set up monitoring and alerting
- Configure backup strategy
- Review security settings
