## Local Setup Checklist (Patroni + Consul + HAProxy, Supabase-ready) - Docker Only

This guide sets up everything on a single local machine using **Docker only** (no Kubernetes required):

- 3 Consul servers in Docker (forming a Raft cluster)
- 3 Patroni PostgreSQL nodes in Docker Compose (simulating 3 VMs)
- Optional HAProxy in Docker for load balancing
- Supabase SQL bootstraps on first cluster initialization

Conventions for host addressing from containers:

- Windows/WSL: use `host.docker.internal`
- Linux/macOS: use your host IP (example method shown below)
- Single host: containers can communicate via container names within Docker networks

Tip: Keep this file open and tick boxes as you complete steps. Record any errors in the provided blocks and update with the fix you applied.

---

### Step 0 — Update Consul Server Addresses in Compose Files

**IMPORTANT**: Before starting, you must update the `retry-join` addresses in each docker-compose file.

For **single host** setup, replace `<VM1_IP>`, `<VM2_IP>`, `<VM3_IP>` with `host.docker.internal` (Windows/WSL) or your host IP (Linux/macOS):

Example for Windows/WSL in `docker-compose.vm1.yml`:
```yaml
-retry-join=host.docker.internal:8304
-retry-join=host.docker.internal:8307
```

Example for Linux/macOS in `docker-compose.vm1.yml` (replace with your actual host IP):
```yaml
-retry-join=192.168.1.100:8304
-retry-join=192.168.1.100:8307
```

For **multi-VM** setup, replace with actual VM IP addresses:
- In `docker-compose.vm1.yml`: replace `<VM2_IP>` and `<VM3_IP>` with VM2 and VM3 IPs
- In `docker-compose.vm2.yml`: replace `<VM1_IP>` and `<VM3_IP>` with VM1 and VM3 IPs
- In `docker-compose.vm3.yml`: replace `<VM1_IP>` and `<VM2_IP>` with VM1 and VM2 IPs

### Global variables (set once per terminal)

- Windows/WSL PowerShell (for reference) or Git Bash/WSL shell

```bash
# Windows/WSL: containers reach host via host.docker.internal
export HOST_ADDR=host.docker.internal

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

### Step 2 — Bring up all VMs together

**IMPORTANT**: Start all three nodes within a short time window (30-60 seconds) so the Consul servers can find each other and establish quorum.

- [ ] Ensure env exported: All CONNECT_ADDRESS and RESTAPI_CONNECT_ADDRESS variables, POSTGRES_PASSWORD, REPLICATION_PASSWORD
- [ ] docker-compose -f docker-compose.vm1.yml up -d
- [ ] docker-compose -f docker-compose.vm2.yml up -d
- [ ] docker-compose -f docker-compose.vm3.yml up -d
- [ ] docker-compose -f docker-compose.vm1.yml ps (both consul-server and patroni-postgres should be starting/up)
- [ ] docker-compose -f docker-compose.vm2.yml ps
- [ ] docker-compose -f docker-compose.vm3.yml ps

Problems encountered (Step 2):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 3 — Verify Consul Cluster Formation

Wait 30-60 seconds for Consul servers to bootstrap and elect a leader.

- [ ] Check Consul members: `docker exec consul-server-vm1 consul members`
- [ ] Verify 3 servers visible with status "alive"
- [ ] Check Consul leader: `docker exec consul-server-vm1 consul operator raft list-peers`
- [ ] Access Consul UI at http://localhost:8500 (or http://$HOST_ADDR:8500)
- [ ] Verify services tab shows "consul" service

Problems encountered (Step 3):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 4 — Optional: Deploy HAProxy for Load Balancing

Choose **Option A** (Docker) or **Option B** (Kubernetes/Minikube) based on your deployment preference.

#### Option A: HAProxy in Docker (Simple)

HAProxy provides a single endpoint for your applications. Skip this if connecting directly to Patroni nodes.

- [ ] Review/update haproxy/haproxy.cfg to match your server names
- [ ] Create docker-compose.haproxy.yml (see README for example)
- [ ] docker-compose -f docker-compose.haproxy.yml up -d
- [ ] Access HAProxy stats at http://localhost:7000 (admin/password)
- [ ] Verify backends show Patroni nodes

#### Option B: HAProxy in Kubernetes (Minikube or Production)

Deploy HAProxy in Kubernetes to simulate a production environment or for actual production use.

**Prerequisites:**
- [ ] Kubernetes cluster accessible: `kubectl cluster-info`
- [ ] Docker Patroni cluster running (Steps 1-3 completed) **OR** Patroni running elsewhere
- [ ] Network connectivity from K8s pods to Patroni nodes verified

**Determine Your Setup:**

Choose the appropriate configuration based on where your Patroni cluster runs:

**Setup 1: Patroni in Docker on Same Host as Minikube**
- Best for: Local development and testing
- Network: Minikube can reach host via `host.minikube.internal` (typically `192.168.65.254`)

**Setup 2: Patroni in Docker on Different Host from K8s Cluster**
- Best for: K8s in cloud (EKS/GKE/AKS) or different servers
- Network: Use public/private IP of Docker host (must be routable from K8s nodes)
- **Important**: Ensure K8s nodes can reach Docker host IP and ports 5432-5434, 8008-8010

**Setup 3: Patroni Already in Kubernetes**
- Best for: Full production K8s deployment
- Network: Use Kubernetes service names or pod IPs directly
- **Note**: Use `k8s/haproxy-deployment.yaml` with Consul DNS instead

---

**Configuration for Setup 1 (Minikube + Docker on Same Host):**

- [ ] Get Minikube host gateway: `kubectl run test --image=busybox:1.35 --restart=Never --rm -it -- nslookup host.minikube.internal`
- [ ] Note the IP (typically `192.168.65.254` on Windows/WSL)
- [ ] Edit `k8s/haproxy-deployment-docker.yaml`
- [ ] Set backend IPs to host gateway:
  ```yaml
  server patroni-vm1 192.168.65.254:5432 maxconn 100 check port 8008
  server patroni-vm2 192.168.65.254:5433 maxconn 100 check port 8009
  server patroni-vm3 192.168.65.254:5434 maxconn 100 check port 8010
  ```

**Configuration for Setup 2 (Cloud K8s + Docker on Different Host):**

- [ ] Get Docker host IP: `echo $HOST_ADDR` or `ipconfig` / `ip addr`
- [ ] Verify K8s nodes can reach Docker host:
  ```bash
  kubectl run test --image=busybox:1.35 --restart=Never --rm -it -- ping <DOCKER_HOST_IP>
  ```
- [ ] Edit `k8s/haproxy-deployment-docker.yaml`
- [ ] Set backend IPs to Docker host IP (e.g., `192.168.2.60`):
  ```yaml
  server patroni-vm1 192.168.2.60:5432 maxconn 100 check port 8008
  server patroni-vm2 192.168.2.60:5433 maxconn 100 check port 8009
  server patroni-vm3 192.168.2.60:5434 maxconn 100 check port 8010
  ```
- [ ] **Cloud-specific**: May need to configure security groups/firewall rules:
  - **AWS**: Update EC2 security groups to allow inbound from K8s VPC
  - **GCP**: Update VPC firewall rules
  - **Azure**: Update Network Security Groups (NSG)

**Configuration for Setup 3 (All in Kubernetes):**

- [ ] Use `k8s/haproxy-deployment.yaml` (Consul DNS-based service discovery)
- [ ] Follow original Kubernetes deployment guide
- [ ] No external Docker containers needed

**Deploy HAProxy to Kubernetes:**
- [ ] Deploy: `kubectl apply -f k8s/haproxy-deployment-docker.yaml`
- [ ] Wait for pod to be ready: `kubectl get pods -n hapostgresql`
- [ ] Check logs: `kubectl logs -l app=haproxy -n hapostgresql --tail=30`
- [ ] Verify HAProxy is connecting to Patroni (should see "UP" for leader and replicas)

**Get Service Endpoints:**

The current configuration uses NodePort. For production, you may want to change to LoadBalancer.

**For Minikube / NodePort (Development):**
- [ ] Get Minikube IP: `minikube ip` (example: `192.168.49.2`)
- [ ] Get NodePort: `kubectl get svc -n hapostgresql haproxy-nodeport`
- [ ] Note the NodePort mappings:
  - PostgreSQL Master: `<MINIKUBE_IP>:30432`
  - PostgreSQL Replicas: `<MINIKUBE_IP>:30001`
  - HAProxy Stats: `http://<MINIKUBE_IP>:30700`

**For Production K8s / LoadBalancer (Cloud):**
- [ ] Change service type in `k8s/haproxy-deployment-docker.yaml`:
  ```yaml
  spec:
    type: LoadBalancer  # Change from NodePort
  ```
- [ ] Redeploy: `kubectl apply -f k8s/haproxy-deployment-docker.yaml`
- [ ] Get external IP: `kubectl get svc -n hapostgresql haproxy-nodeport -o wide`
  - **AWS EKS**: Will provision Network Load Balancer (NLB)
  - **GCP GKE**: Will provision TCP Load Balancer
  - **Azure AKS**: Will provision Azure Load Balancer
- [ ] Wait for `EXTERNAL-IP` to show (may take 2-5 minutes)
- [ ] Note the endpoints:
  - PostgreSQL Master: `<EXTERNAL-IP>:5432`
  - PostgreSQL Replicas: `<EXTERNAL-IP>:5001`
  - HAProxy Stats: `http://<EXTERNAL-IP>:7000`

**For Production K8s / Ingress (Advanced):**
- [ ] For TCP services, use Ingress controller that supports TCP (e.g., nginx-ingress with TCP ConfigMap)
- [ ] Configure TCP service exposure via Ingress controller
- [ ] See cloud provider documentation for TCP Ingress setup

**Verify HAProxy Status:**
- [ ] Access HAProxy stats:
  - Minikube: Open `http://<MINIKUBE_IP>:30700`
  - LoadBalancer: Open `http://<EXTERNAL-IP>:7000`
- [ ] Verify backend status:
  - `postgres_master` backend: patroni-vm1 should show **UP** (green)
  - `postgres_replicas` backend: patroni-vm2 and patroni-vm3 should show **UP** (green)
- [ ] Servers showing "DOWN" with 503 errors are normal - they're not the current master/replica

**Test PostgreSQL Connection through HAProxy:**
- [ ] Minikube: `psql -h <MINIKUBE_IP> -p 30432 -U postgres -c "SELECT version();"`
- [ ] LoadBalancer: `psql -h <EXTERNAL-IP> -p 5432 -U postgres -c "SELECT version();"`
- [ ] Or using Docker: `docker run --rm postgres:15 psql "postgresql://postgres:<PASSWORD>@<ENDPOINT>:<PORT>/postgres" -c "SELECT version();"`

Problems encountered (Step 4):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 5 — Verify Patroni Cluster Formation

Wait another 30-60 seconds for Patroni to register with Consul and elect a leader.

- [ ] Check Patroni cluster: `docker exec patroni-postgres-vm1 patronictl list`
- [ ] Verify one node shows as "Leader" and two as "Replica"
- [ ] Check replication lag is 0 or very small
- [ ] Verify Supabase schemas applied once: `psql -h $HOST_ADDR -p 5432 -U postgres -d postgres -c "\\dn" | grep -E 'auth|storage|realtime|\_analytics|\_realtime|graphql_public'`
- [ ] Test connection to primary: `psql -h $HOST_ADDR -p 5432 -U postgres -c "SELECT version();"`
- [ ] Verify Patroni registered in Consul: `docker exec consul-server-vm1 consul catalog services` (should show "patroni")

Problems encountered (Step 5):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 6 — Deploy Supabase with External PostgreSQL via HAProxy

Deploy Supabase services in Kubernetes, connecting to the Patroni PostgreSQL cluster through HAProxy.

#### 6.1 - Initialize Supabase Schema in PostgreSQL

**Run Supabase initialization SQL on the Patroni cluster:**

Choose your connection method:

**Option A: Via HAProxy LoadBalancer (Recommended for Production)**
- [ ] Get HAProxy external IP: `kubectl get svc haproxy-loadbalancer -n hapostgresql`
- [ ] Run initialization script:
  ```bash
  # Using psql from local machine or Docker
  psql -h <EXTERNAL-IP> -p 5432 -U postgres -d postgres -f scripts/init-supabase-db.sql
  
  # Or using Docker
  docker run --rm -v $(pwd)/scripts:/scripts postgres:15 psql -h <EXTERNAL-IP> -p 5432 -U postgres -d postgres -f /scripts/init-supabase-db.sql
  ```

**Option B: Via Direct Patroni Connection (Development)**
- [ ] Run initialization script:
  ```bash
  psql -h localhost -p 5432 -U postgres -d postgres -f scripts/init-supabase-db.sql
  ```

**Option C: Via Patroni Container (Quick method)**
- [ ] Copy script into container and execute:
  ```bash
  # Windows PowerShell
  docker cp scripts/init-supabase-db.sql patroni-postgres-vm1:/tmp/
  Get-Content env.local | Select-String "POSTGRES_PASSWORD=" | ForEach-Object { $_.ToString().Split('=')[1].Trim() } | Set-Variable -Name PG_PASS; docker exec -e PGPASSWORD=$PG_PASS patroni-postgres-vm1 psql -U postgres -d postgres -f /tmp/init-supabase-db.sql

  # Linux/macOS
  docker cp scripts/init-supabase-db.sql patroni-postgres-vm1:/tmp/
  export PG_PASS=$(grep '^POSTGRES_PASSWORD=' env.local | cut -d'=' -f2 | tr -d '\r') && docker exec -e PGPASSWORD="$PG_PASS" patroni-postgres-vm1 psql -U postgres -d postgres -f /tmp/init-supabase-db.sql
  ```

**Verify initialization:**
- [ ] Check schemas created:
  ```bash
  psql -h <HOST> -p <PORT> -U postgres -d postgres -c "\dn" | grep -E 'auth|storage|realtime'
  ```
- [ ] Verify extensions installed:
  ```bash
  psql -h <HOST> -p <PORT> -U postgres -d postgres -c "\dx" | grep -E 'uuid-ossp|pgcrypto'
  ```
- [ ] Check tables created:
  ```bash
  psql -h <HOST> -p <PORT> -U postgres -d postgres -c "\dt auth.*" | head -10
  ```

#### 6.2 - Prepare Supabase Helm Configuration

**Update Helm values for HAProxy connection:**

- [ ] Copy example values: `cp supabase-helm/values-patroni.yaml supabase-helm/values-haproxy.yaml`
- [ ] Edit `supabase-helm/values-haproxy.yaml`

**For LoadBalancer (Production - Recommended):**
- [ ] Update database host to use K8s internal service:
  ```yaml
  auth:
    environment:
      DB_HOST: haproxy-loadbalancer.hapostgresql.svc.cluster.local
      DB_PORT: "5432"
      DB_USER: postgres
      DB_NAME: postgres
  ```
- [ ] Apply same to: `rest`, `realtime`, `meta`, `storage`, `analytics`, `functions`

**For NodePort (Development/Minikube):**
- [ ] Update database host to use Minikube IP:
  ```yaml
  auth:
    environment:
      DB_HOST: <MINIKUBE_IP>
      DB_PORT: "30432"  # NodePort for HAProxy
      DB_USER: postgres
      DB_NAME: postgres
  ```

**Update secrets:**
- [ ] Update `secret.db.password` to match your `POSTGRES_PASSWORD`
- [ ] Generate new JWT secret (at least 32 characters):
  ```bash
  openssl rand -base64 32
  ```
- [ ] Update dashboard credentials
- [ ] Update SMTP settings (if using email auth)

**Update external URLs:**
- [ ] For LoadBalancer: Set `API_EXTERNAL_URL` to LoadBalancer IP/DNS
- [ ] For Minikube: Set to Minikube IP with appropriate port
- [ ] Update `GOTRUE_SITE_URL` similarly

#### 6.3 - Deploy Supabase via Helm

**Add Supabase Helm repository:**
- [ ] Add repo: `helm repo add supabase https://supabase.github.io/supabase-kubernetes`
- [ ] Update repo: `helm repo update`
- [ ] Search versions: `helm search repo supabase -l | head -10`

**Deploy Supabase:**
- [ ] Create namespace: `kubectl create namespace supabase` (or use existing)
- [ ] Install Supabase:
  ```bash
  helm install supabase supabase/supabase \
    --namespace supabase \
    --values supabase-helm/values-haproxy.yaml \
    --create-namespace
  ```
- [ ] Watch deployment: `kubectl get pods -n supabase -w`
- [ ] Wait for all pods to be Ready (may take 3-5 minutes)

**Verify deployment:**
- [ ] Check all pods running: `kubectl get pods -n supabase`
- [ ] Check services: `kubectl get svc -n supabase`
- [ ] View logs of auth service: `kubectl logs -n supabase -l app=supabase-auth --tail=50`
- [ ] View logs of rest service: `kubectl logs -n supabase -l app=supabase-rest --tail=50`

#### 6.4 - Expose Supabase Services

**For Production (LoadBalancer):**
- [ ] Check if Kong service has LoadBalancer:
  ```bash
  kubectl get svc -n supabase | grep kong
  ```
- [ ] Get external IP: `kubectl get svc supabase-kong -n supabase -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
- [ ] Or DNS: `kubectl get svc supabase-kong -n supabase -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

**For Development (Minikube/NodePort):**
- [ ] Get Minikube IP: `minikube ip`
- [ ] Get NodePort: `kubectl get svc supabase-kong -n supabase`
- [ ] Supabase API endpoint: `http://<MINIKUBE_IP>:<KONG_NODEPORT>`

**For Local Access (Port Forward):**
- [ ] Port forward Kong API:
  ```bash
  kubectl port-forward -n supabase svc/supabase-kong 8000:8000
  ```
- [ ] Port forward Studio (UI):
  ```bash
  kubectl port-forward -n supabase svc/supabase-studio 3000:3000
  ```
- [ ] Access Studio at: `http://localhost:3000`

#### 6.5 - Test Supabase Connection

**Test database connectivity from Supabase:**
- [ ] Check auth service connects to database:
  ```bash
  kubectl logs -n supabase -l app=supabase-auth | grep -i "database\|connection\|error"
  ```
- [ ] Check rest (PostgREST) service:
  ```bash
  kubectl logs -n supabase -l app=supabase-rest | grep -i "connected\|error"
  ```

**Test Supabase API:**
- [ ] Get Supabase URL and anon key from values file
- [ ] Test REST API:
  ```bash
  curl http://<SUPABASE_URL>/rest/v1/ \
    -H "apikey: <ANON_KEY>" \
    -H "Authorization: Bearer <ANON_KEY>"
  ```
- [ ] Should return Supabase API response (not error)

**Test Supabase Studio:**
- [ ] Access Studio UI at exposed endpoint
- [ ] Login with dashboard credentials from values file
- [ ] Verify tables visible in Table Editor
- [ ] Check SQL Editor works
- [ ] Verify auth.users table is accessible

**Create test user via API:**
- [ ] Test signup endpoint:
  ```bash
  curl -X POST http://<SUPABASE_URL>/auth/v1/signup \
    -H "apikey: <ANON_KEY>" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"testpassword123"}'
  ```
- [ ] Verify user created:
  ```bash
  psql -h <HAProxy_HOST> -p <PORT> -U postgres -d postgres -c "SELECT email, created_at FROM auth.users;"
  ```

#### 6.6 - Verify End-to-End Integration

**Verify the complete flow:**
- [ ] Supabase services running in K8s ✓
- [ ] Supabase connects to HAProxy in K8s ✓
- [ ] HAProxy routes to Patroni in Docker ✓
- [ ] Patroni cluster healthy with replication ✓
- [ ] Data written via Supabase API appears in all Patroni replicas ✓

**Test data replication:**
- [ ] Create data via Supabase API or Studio
- [ ] Verify data on primary:
  ```bash
  docker exec patroni-postgres-vm1 psql -U postgres -c "SELECT count(*) FROM auth.users;"
  ```
- [ ] Verify data replicated to replica:
  ```bash
  docker exec patroni-postgres-vm2 psql -U postgres -c "SELECT count(*) FROM auth.users;"
  ```
- [ ] Counts should match (replication working) ✓

Problems encountered (Step 6):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Step 7 — Optional: Spring Boot Application Integration

Connect the sample Spring Boot application to PostgreSQL via HAProxy.

**Update Application Configuration:**
- [ ] Edit `spring-app/src/main/resources/application.properties`
- [ ] Update the JDBC URL based on your deployment:

**For HAProxy in Docker:**
```properties
spring.datasource.url=jdbc:postgresql://localhost:5000/postgres
```

**For HAProxy in Minikube (NodePort):**
```properties
spring.datasource.url=jdbc:postgresql://192.168.49.2:30432/postgres
```

**For HAProxy in Cloud K8s (LoadBalancer):**
```properties
# Replace with your LoadBalancer's EXTERNAL-IP
spring.datasource.url=jdbc:postgresql://a1b2c3d4.us-west-2.elb.amazonaws.com:5432/postgres
# OR with IP
spring.datasource.url=jdbc:postgresql://35.123.45.67:5432/postgres
```

**For HAProxy in K8s from App Also in K8s:**
```properties
# Use Kubernetes internal service name
spring.datasource.url=jdbc:postgresql://postgres-master.hapostgresql.svc.cluster.local:5432/postgres
```

**For Direct Connection to Patroni:**
```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/postgres
```

- [ ] Update username: `spring.datasource.username=postgres`
- [ ] Update password: `spring.datasource.password=<YOUR_POSTGRES_PASSWORD>`

Example configuration for HAProxy in Minikube:
```properties
spring.datasource.url=jdbc:postgresql://192.168.49.2:30432/postgres
spring.datasource.username=postgres
spring.datasource.password=mysecurepassword123
```

**Build and Run Spring Boot Application:**
- [ ] Navigate to spring-app directory: `cd spring-app`
- [ ] Build: `mvn clean package` (or skip tests: `mvn clean package -DskipTests`)
- [ ] Run: `mvn spring-boot:run`
- [ ] Wait for application to start (watch for "Started DemoApplication" in logs)

**Test Application:**
- [ ] Test health endpoint: `curl http://localhost:8080/actuator/health` (if actuator enabled)
- [ ] Test books API: `curl http://localhost:8080/books`
- [ ] Create a book: `curl -X POST http://localhost:8080/books -H "Content-Type: application/json" -d '{"title":"Test Book","author":"Test Author"}'`
- [ ] Verify book created: `curl http://localhost:8080/books`

**Verify Database Connection:**
- [ ] Check application logs for successful database connection
- [ ] Verify no connection errors in logs
- [ ] Check Patroni cluster still healthy: `docker exec patroni-postgres-vm1 patronictl -c /tmp/patroni.yml list`
- [ ] Check HAProxy stats show active connections: Open `http://<MINIKUBE_IP>:30700` (for Minikube) or `http://localhost:7000` (for Docker)

Problems encountered (Step 7):

- Observed error:
- Root cause:
- Fix applied:
- Validated by:

---

### Final Verification

Run these commands to verify everything is working:

**Consul Cluster:**

```bash
# Check all Consul servers are members
docker exec consul-server-vm1 consul members

# Verify Consul leader elected
docker exec consul-server-vm1 consul operator raft list-peers

# Check registered services
docker exec consul-server-vm1 consul catalog services
```

**Patroni Cluster:**

```bash
# Check Patroni cluster status
docker exec patroni-postgres-vm1 patronictl list

# Should show one Leader and two Replicas with 0 or minimal lag
```

**Database Connectivity:**

```bash
# Test connection to primary
psql -h $HOST_ADDR -p 5432 -U postgres -c "SELECT version();"

# Check Supabase schemas (if initialized)
psql -h $HOST_ADDR -p 5432 -U postgres -d postgres -c "\\dn" | grep -E 'auth|storage|realtime|_analytics|_realtime|graphql_public'
```

**All Services Running:**

```bash
# Check all containers are up
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "consul-server|patroni-postgres"
```

Problems encountered and resolved:

1. **Container recreation issues**
   - Observed error: Containers being repeatedly recreated
   - Root cause: Shared volumes across docker-compose files without unique project names
   - Fix applied: Added `-p vmX` to all docker-compose commands in start/stop scripts
   - Validated by: Containers now start/stop cleanly without recreation

2. **Entrypoint script not found**
   - Observed error: `/entrypoint.sh: no such file or directory`
   - Root cause: Windows CRLF line endings in shell script
   - Fix applied: Converted entrypoint.sh to LF line endings
   - Validated by: Container started successfully

3. **Consul cluster not forming**
   - Observed error: Consul members showed "failed" on different networks
   - Root cause: Each docker-compose created isolated networks
   - Fix applied: Created shared bridge network `patroni-shared-bridge`, updated all compose files to use it with container names for retry-join
   - Validated by: `docker exec consul-server-vm1 consul members` shows all 3 servers alive

4. **Patroni YAML parsing error**
   - Observed error: `ValueError: invalid literal for int() with base 10: '8500}'`
   - Root cause: Patroni doesn't support `:-` default value syntax in YAML
   - Fix applied: Removed `:-` syntax, hard-coded consul host, added envsubst preprocessing in entrypoint
   - Validated by: Patroni started without YAML errors

5. **PostgreSQL data directory permission errors**
   - Observed error: `FATAL: data directory "/home/postgres/pgdata/pgroot/data" has invalid permissions`
   - Root cause: Replica data directories didn't have correct permissions (0700)
   - Fix applied: Modified Dockerfile to run as root with gosu, updated entrypoint to fix permissions then switch to postgres user
   - Validated by: All 3 Patroni instances started successfully

6. **HAProxy in Kubernetes/Minikube**
   - Observed challenge: Minikube pods can't reach Docker containers on default host IP
   - Root cause: Minikube runs in isolated VM, needs special gateway IP
   - Fix applied: Used `host.minikube.internal` (resolves to 192.168.65.254), configured HAProxy backends to use this IP
   - Additional fix: Health check endpoint changed to port 7001 (no auth) to avoid HTTP 401 errors from K8s probes
   - Validated by: HAProxy pod running, stats showing patroni-vm1 UP on master, patroni-vm2/vm3 UP on replicas

7. **HAProxy in Cloud Kubernetes (EKS/GKE/AKS)**
   - Common issues:
     - **Network connectivity**: K8s pods can't reach external Docker host
       - Fix: Verify security groups/firewall rules allow inbound from K8s VPC/subnet
       - Fix: Use routable IP addresses (private or public depending on setup)
     - **LoadBalancer pending**: External-IP stays in "Pending" state
       - Cause: Cloud provider doesn't support LoadBalancer type or IAM permissions missing
       - Fix: Verify cloud provider integration, check IAM/service account permissions
       - Alternative: Use NodePort or Ingress instead
     - **Connection timeout**: HAProxy connects but PostgreSQL times out
       - Cause: Security groups blocking database ports (5432-5434) or Patroni API ports (8008-8010)
       - Fix: Open required ports in cloud security groups/firewall rules
     - **DNS resolution failures**: Can't resolve hostnames
       - Cause: CoreDNS issues or network policy blocking DNS
       - Fix: Verify CoreDNS pods running, check NetworkPolicy if used

**✅ Final Status**: All components operational

**Docker Components:**
- Consul cluster: 3/3 servers alive in Docker
- Patroni cluster: 1 leader (vm1) + 2 replicas (vm2, vm3) streaming in Docker

**Kubernetes Components (depending on deployment):**
- HAProxy in Minikube: Running, successfully routing to Docker Patroni nodes via `host.minikube.internal`
- HAProxy in Cloud K8s: Running, routing to external Patroni via routable IP addresses
- Service exposure:
  - Minikube: NodePort at `<MINIKUBE_IP>:30432`
  - Cloud K8s: LoadBalancer at `<EXTERNAL-IP>:5432` (or NodePort as fallback)

**Application Integration:**
- PostgreSQL: All databases accessible via HAProxy
- Spring Boot: Application.properties configured to use appropriate HAProxy endpoint
- Connection verified through load balancer

**Endpoints Summary:**
- Development (Minikube): `jdbc:postgresql://192.168.49.2:30432/postgres`
- Production (Cloud K8s): `jdbc:postgresql://<EXTERNAL-IP>:5432/postgres`
- Internal (App in K8s): `jdbc:postgresql://postgres-master.hapostgresql.svc.cluster.local:5432/postgres`

---

### Appendix — Quick references

**Find host IP (Linux/macOS):**

```bash
ip route get 1.1.1.1 | awk '{print $7; exit}'
```

**Windows host IP (PowerShell):**

```powershell
Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null} | ForEach-Object {$_.IPv4Address.IPAddress}
```

Note: On Windows/WSL, prefer `host.docker.internal` from containers to reach the host.

**Minikube-Specific Commands:**

```bash
# Get Minikube IP
minikube ip

# Get Minikube host gateway IP (from inside pod)
kubectl run test --image=busybox:1.35 --restart=Never --rm -it -- nslookup host.minikube.internal

# Access service via Minikube tunnel (alternative to NodePort)
minikube service haproxy-nodeport -n hapostgresql --url
```

**Kubernetes Commands (All Clusters):**

```bash
# Check cluster info
kubectl cluster-info
kubectl get nodes

# Check HAProxy pod status
kubectl get pods -n hapostgresql
kubectl get pods -n hapostgresql -o wide  # Shows node placement

# View HAProxy logs
kubectl logs -l app=haproxy -n hapostgresql --tail=50
kubectl logs -l app=haproxy -n hapostgresql -f  # Follow logs

# Check HAProxy service
kubectl get svc -n hapostgresql
kubectl get svc -n hapostgresql -o wide
kubectl describe svc haproxy-nodeport -n hapostgresql

# Delete and redeploy HAProxy
kubectl delete -f k8s/haproxy-deployment-docker.yaml
kubectl apply -f k8s/haproxy-deployment-docker.yaml

# Check rollout status
kubectl rollout status deployment/haproxy -n hapostgresql

# Access HAProxy stats from pod
kubectl exec -n hapostgresql $(kubectl get pod -n hapostgresql -l app=haproxy -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://127.0.0.1:7000

# Port forward to access services locally
kubectl port-forward -n hapostgresql svc/haproxy-nodeport 5432:5432
kubectl port-forward -n hapostgresql svc/haproxy-nodeport 7000:7000

# Test network connectivity from pod to Patroni
kubectl run test --image=busybox:1.35 --restart=Never --rm -it -n hapostgresql -- sh
# Then inside pod: ping <PATRONI_HOST>, telnet <PATRONI_HOST> 5432
```

**Cloud Provider Specific Commands:**

```bash
# AWS EKS - Get LoadBalancer DNS
kubectl get svc haproxy-nodeport -n hapostgresql -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# GCP GKE - Get LoadBalancer IP
kubectl get svc haproxy-nodeport -n hapostgresql -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Azure AKS - Get LoadBalancer IP
kubectl get svc haproxy-nodeport -n hapostgresql -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Check cloud provider annotations
kubectl get svc haproxy-nodeport -n hapostgresql -o yaml | grep annotations -A 10
```

**Connection Strings for Different Setups:**

```bash
# Direct to Patroni primary (Docker on localhost)
jdbc:postgresql://localhost:5432/postgres

# HAProxy in Docker (master endpoint port 5000)
jdbc:postgresql://localhost:5000/postgres

# HAProxy in Minikube with NodePort (replace 192.168.49.2 with your Minikube IP)
jdbc:postgresql://192.168.49.2:30432/postgres

# HAProxy in Minikube with port-forward
jdbc:postgresql://localhost:5432/postgres

# HAProxy in Cloud K8s with LoadBalancer (AWS example - uses DNS)
jdbc:postgresql://a1b2c3d4-12345.us-west-2.elb.amazonaws.com:5432/postgres

# HAProxy in Cloud K8s with LoadBalancer (GCP/Azure example - uses IP)
jdbc:postgresql://35.123.45.67:5432/postgres

# HAProxy in K8s from app also in K8s (same cluster - internal service)
jdbc:postgresql://postgres-master.hapostgresql.svc.cluster.local:5432/postgres

# HAProxy in K8s from app in different namespace (full FQDN)
jdbc:postgresql://postgres-master.hapostgresql.svc.cluster.local:5432/postgres
```

**Port Mappings Reference:**

| Service | Docker Port | Minikube NodePort | LoadBalancer Port | K8s Internal |
|---------|-------------|-------------------|-------------------|--------------|
| PostgreSQL Master | 5000 | 30432 | 5432 | 5432 |
| PostgreSQL Replica | 5001 | 30001 | 5001 | 5001 |
| HAProxy Stats | 7000 | 30700 | 7000 | 7000 |
| Patroni API (vm1) | 8008 | - | - | - |
| Patroni API (vm2) | 8009 | - | - | - |
| Patroni API (vm3) | 8010 | - | - | - |
