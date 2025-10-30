## Local Setup Checklist (Patroni + Consul + HAProxy, Supabase-ready)

This guide sets up everything on a single local machine:

- Consul servers and HAProxy in Kubernetes
- 3 Patroni PostgreSQL nodes in Docker Compose (simulating 3 VMs)
- Consul agents run alongside each Patroni node
- Supabase SQL bootstraps on first cluster initialization

Conventions for host addressing from containers:

- Windows/WSL: use `host.docker.internal`
- Linux/macOS: use your host IP (example method shown below)

Tip: Keep this file open and tick boxes as you complete steps. Record any errors in the provided blocks and update with the fix you applied.

---

### Global variables (set once per terminal)

- Windows/WSL PowerShell (for reference) or Git Bash/WSL shell

```bash
# Windows/WSL: containers reach host via host.docker.internal
export HOST_ADDR=host.docker.internal

# Consul agent DNS endpoints (mapped by our compose files)
export CONSUL_DNS1="$HOST_ADDR:8600"
export CONSUL_DNS2="$HOST_ADDR:8601"
export CONSUL_DNS3="$HOST_ADDR:8602"

# Patroni advertised addresses per node
export CONNECT_ADDRESS_VM1="$HOST_ADDR:5432"
export CONNECT_ADDRESS_VM2="$HOST_ADDR:5433"
export CONNECT_ADDRESS_VM3="$HOST_ADDR:5434"
export RESTAPI_CONNECT_ADDRESS_VM1="$HOST_ADDR:8008"
export RESTAPI_CONNECT_ADDRESS_VM2="$HOST_ADDR:8009"
export RESTAPI_CONNECT_ADDRESS_VM3="$HOST_ADDR:8010"

# Database passwords
export POSTGRES_PASSWORD=your-secure-postgres-password
export REPLICATION_PASSWORD=your-secure-replication-password
```

- Linux/macOS

```bash
# Discover host IP (pick a primary interface if this returns multiple)
export HOST_ADDR=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# Consul agent DNS endpoints (mapped by our compose files)
export CONSUL_DNS1="$HOST_ADDR:8600"
export CONSUL_DNS2="$HOST_ADDR:8601"
export CONSUL_DNS3="$HOST_ADDR:8602"

# Patroni advertised addresses per node
export CONNECT_ADDRESS_VM1="$HOST_ADDR:5432"
export CONNECT_ADDRESS_VM2="$HOST_ADDR:5433"
export CONNECT_ADDRESS_VM3="$HOST_ADDR:5434"
export RESTAPI_CONNECT_ADDRESS_VM1="$HOST_ADDR:8008"
export RESTAPI_CONNECT_ADDRESS_VM2="$HOST_ADDR:8009"
export RESTAPI_CONNECT_ADDRESS_VM3="$HOST_ADDR:8010"

# Database passwords
export POSTGRES_PASSWORD=your-secure-postgres-password
export REPLICATION_PASSWORD=your-secure-replication-password
```

Problems encountered (global):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 1 — Build Patroni image (local)

- [x] docker build -f docker/Dockerfile.patroni -t patroni-postgres:local .
- [x] Verify patroni[consul] installed (image build logs should show)
- [x] Verify image present: `docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | findstr patroni-postgres`
- [x] Verify libs without entrypoint: `docker run --rm --entrypoint python3 patroni-postgres:local -c "import patroni, consul; print('ok')"` (got `ok`)

Problems encountered (Step 1):

- Observed error: Initial validation using default entrypoint hung waiting for Consul
- Root cause: Image entrypoint waits for Consul leader at `consul-agent:8500`
- Fix applied: Override entrypoint to run Python directly with `--entrypoint python3`
- Validated by: Output `ok` from import test

---

### Step 2 — Bring up VM1 (Primary) with Supabase bootstrap

Note: Patroni will wait until Consul servers are up (configured in Step 4).

- [ ] Ensure env exported: CONNECT_ADDRESS_VM1, RESTAPI_CONNECT_ADDRESS_VM1, POSTGRES_PASSWORD, REPLICATION_PASSWORD
- [ ] docker-compose -f docker-compose.vm1.yml up -d
- [ ] docker-compose -f docker-compose.vm1.yml ps (both consul-agent and patroni-postgres up; Patroni may be waiting)

Problems encountered (Step 2):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 3 — Bring up VM2 and VM3 (Replicas)

Note: These may also wait for Consul until Step 4 is complete.

- [ ] Ensure env exported: CONNECT_ADDRESS_VM2/RESTAPI_CONNECT_ADDRESS_VM2; CONNECT_ADDRESS_VM3/RESTAPI_CONNECT_ADDRESS_VM3
- [ ] docker-compose -f docker-compose.vm2.yml up -d
- [ ] docker-compose -f docker-compose.vm3.yml up -d

Problems encountered (Step 3):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 4 — Kubernetes: Consul servers (Minikube)

- [ ] kubectl apply -f k8s/consul-cluster.yaml
- [ ] kubectl get pods -n consul -l app=consul (3 Running)
- [ ] UI via port-forward: kubectl port-forward -n consul svc/consul-ui 8500:8500 (open http://localhost:8500)
- [ ] NodePort reachable: curl http://$(minikube ip):32500/v1/status/leader (should return a leader address)

Problems encountered (Step 4):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 5 — Kubernetes: HAProxy using local Consul agent DNS

- [ ] Edit k8s/haproxy-deployment.yaml (Deployment env) to set:
  - [ ] CONSUL_DNS1=$CONSUL_DNS1
  - [ ] CONSUL_DNS2=$CONSUL_DNS2
  - [ ] CONSUL_DNS3=$CONSUL_DNS3
- [ ] kubectl apply -f k8s/haproxy-deployment.yaml
- [ ] kubectl get pods -n hapostgresql -l app=haproxy (Ready)
- [ ] Port-forward stats: kubectl port-forward -n hapostgresql svc/haproxy-stats 7000:7000 (open http://localhost:7000)

Problems encountered (Step 5):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 6 — Verify Patroni cluster formed

- [ ] docker exec patroni-postgres-vm1 patronictl list (VM1 should be Leader; VM2/VM3 Replicas)
- [ ] Verify Supabase schemas applied once: psql -h $HOST_ADDR -p 5432 -U postgres -d postgres -c "\\dn" | grep -E 'auth|storage|realtime|\_analytics|\_realtime|graphql_public'

Problems encountered (Step 6):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 7 — HAProxy service checks

- [ ] Port-forward stats: kubectl port-forward -n hapostgresql svc/haproxy-stats 7000:7000
- [ ] Validate RW endpoint (primary via postgres-master svc if exposed) or direct to HAProxy service
- [ ] Validate RO pool (postgres-replica svc) lists two replicas

Problems encountered (Step 7):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 8 — Optional: Supabase

- [ ] helm repo add supabase https://supabase.github.io/supabase-kubernetes && helm repo update
- [ ] helm install supabase supabase/supabase -f supabase-helm/values-patroni.yaml
- [ ] kubectl get pods -l app.kubernetes.io/name=supabase (pods Ready)

Problems encountered (Step 8):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Final Verification

- [ ] Patroni cluster

```bash
docker exec patroni-postgres-vm1 patronictl list
```

- [ ] Consul members/services (server-side)

```bash
kubectl exec -n consul deploy/consul -- consul members || true
kubectl exec -n consul deploy/consul -- consul catalog services || true
```

- [ ] Consul agents (per VM)

```bash
docker exec consul-agent-vm1 consul members || true
docker exec consul-agent-vm2 consul members || true
docker exec consul-agent-vm3 consul members || true
```

- [ ] Supabase schemas on primary

```bash
psql -h $HOST_ADDR -p 5432 -U postgres -d postgres -c "\\dn" | grep -E 'auth|storage|realtime|_analytics|_realtime|graphql_public'
```

Problems encountered (Final):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Appendix — Quick references

Find host IP (Linux/macOS):

```bash
ip route get 1.1.1.1 | awk '{print $7; exit}'
```

Windows host IP (PowerShell):

```powershell
Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null} | ForEach-Object {$_.IPv4Address.IPAddress}
```

Note: On Windows/WSL, prefer `host.docker.internal` from containers to reach the host.
