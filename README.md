## PostgreSQL HA with Patroni, Consul, and HAProxy (Supabase-ready)

This repository delivers a working HA PostgreSQL cluster managed by Patroni, coordinated by Consul, fronted by HAProxy, and ready for Supabase. PostgreSQL nodes run in Docker (per VM). A Consul server cluster and HAProxy run in Kubernetes. Each VM runs a Consul agent that joins the Consul servers.

## Topology

```
Kubernetes
  ├─ Consul servers (StatefulSet, 3 replicas)        : DNS/UI via ClusterIP + NodePorts
  └─ HAProxy (Deployment)                             : Resolves Patroni via Consul agents' DNS

VMs / Docker (per VM)
  ├─ Consul agent (joins K8s Consul)                  : exposes 8500 HTTP, 8300/8301/8302, 8600 DNS
  └─ Patroni PostgreSQL                               : 5432/3/4 (PG), 8008/9/10 (Patroni API)

Bootstrap
  └─ First Patroni node runs scripts/init-supabase-db.sql once; replicas stream-replicate
```

## What you get

- 3-node PostgreSQL cluster with automatic failover (Patroni + Consul DCS)
- HAProxy with dynamic backends discovered via Consul DNS
- Supabase schema auto-initialized on first cluster bootstrap
- Single-host demo and multi-VM deployment options

## Prerequisites

- Docker and Docker Compose on each VM/host
- A Kubernetes cluster (Minikube/kind/cloud)
- kubectl configured; Helm 3 (if deploying Supabase)
- On Windows, run commands from WSL2 or Git Bash

## Components and Ports

- PostgreSQL: 5432 (VM1), 5433 (VM2), 5434 (VM3)
- Patroni API: 8008 (VM1), 8009 (VM2), 8010 (VM3)
- Consul agent (per VM): 8500/http, 8300/8301/8302, 8600/dns (tcp+udp)
- Consul servers (K8s): NodePorts 32500/32300/32301/32302/32600

## Step 1: Deploy Consul servers in Kubernetes

```bash
kubectl apply -f k8s/consul-cluster.yaml
```

This creates a 3-node Consul server cluster with UI and DNS inside the cluster and NodePorts for external agents.

## Step 2: Configure HAProxy in Kubernetes to use VM Consul agents

`k8s/haproxy-deployment.yaml` is preconfigured to resolve Patroni backends via Consul agent DNS running on your VMs. Provide the agents' reachable DNS endpoints (VM IP + exposed host ports):

- VM1 agent DNS -> <vm1-ip>:8600
- VM2 agent DNS -> <vm2-ip>:8601
- VM3 agent DNS -> <vm3-ip>:8602

Set these in the HAProxy Deployment env (already templated), then apply:

```bash
kubectl apply -f k8s/haproxy-deployment.yaml
```

If you need to change values, edit the `CONSUL_DNS1/2/3` envs in the Deployment and reapply.

## Step 3: Build Patroni image

```bash
docker build -f docker/Dockerfile.patroni -t patroni-postgres .
```

Image details:

- Patroni with Consul support
- Entrypoint waits for Consul before starting Patroni

## Step 4: Bring up the VMs (Docker Compose)

Each `docker-compose.vmX.yml` runs two containers: a Consul agent and a Patroni PostgreSQL node.

Expose Consul DNS per VM (already configured):

- VM1: host 8600 -> agent 8600 (tcp+udp)
- VM2: host 8601 -> agent 8600 (tcp+udp)
- VM3: host 8602 -> agent 8600 (tcp+udp)

### VM1 (first node; bootstrap + Supabase SQL)

```bash
export POSTGRES_PASSWORD=...
export REPLICATION_PASSWORD=...
export CONNECT_ADDRESS_VM1="<vm1-ip>:5432"
export RESTAPI_CONNECT_ADDRESS_VM1="<vm1-ip>:8008"

docker-compose -f docker-compose.vm1.yml up -d
```

On first initialization only, Patroni runs `scripts/init-supabase-db.sql`. The `./scripts` dir is mounted read-only into the container.

### VM2

```bash
export CONNECT_ADDRESS_VM2="<vm2-ip>:5433"
export RESTAPI_CONNECT_ADDRESS_VM2="<vm2-ip>:8009"

docker-compose -f docker-compose.vm2.yml up -d
```

### VM3

```bash
export CONNECT_ADDRESS_VM3="<vm3-ip>:5434"
export RESTAPI_CONNECT_ADDRESS_VM3="<vm3-ip>:8010"

docker-compose -f docker-compose.vm3.yml up -d
```

Replication will stream from the primary. Schema and data from the bootstrap SQL will appear on replicas.

## Step 5: Optional – Deploy Supabase

```bash
helm repo add supabase https://supabase.github.io/supabase-kubernetes
helm repo update
helm install supabase supabase/supabase -f supabase-helm/values-patroni.yaml
```

`values-patroni.yaml` points Supabase services to HAProxy.

## Verification checklist

```bash
# Consul servers
kubectl get pods -n consul -l app=consul

# HAProxy
kubectl get pods -n hapostgresql -l app=haproxy

# Patroni nodes
docker-compose -f docker-compose.vm1.yml ps
docker-compose -f docker-compose.vm2.yml ps
docker-compose -f docker-compose.vm3.yml ps
docker exec patroni-postgres-vm1 patronictl list

# Supabase schemas on primary
psql -h <vm1-ip> -p 5432 -U postgres -d postgres -c "\\dn" | grep -E 'auth|storage|realtime|_analytics|_realtime|graphql_public'
```

## Operations

- View logs (VM1): `docker-compose -f docker-compose.vm1.yml logs -f`
- Patroni status: `docker exec patroni-postgres-vm1 patronictl list`
- HAProxy stats: `kubectl port-forward -n hapostgresql svc/haproxy-stats 7000:7000`

## Environment variables (key)

- In Patroni containers (via compose/env):
  - `POSTGRES_PASSWORD`, `REPLICATION_PASSWORD`
  - `CONSUL_HOST` (e.g., <minikube-ip>:32500)
  - `CONNECT_ADDRESS` and `RESTAPI_CONNECT_ADDRESS` (set per VM via `CONNECT_ADDRESS_VM*` and `RESTAPI_CONNECT_ADDRESS_VM*`)
- In HAProxy Deployment:
  - `CONSUL_DNS1`, `CONSUL_DNS2`, `CONSUL_DNS3` -> VM Consul agent DNS endpoints

## Troubleshooting (essentials)

- Patroni cannot reach Consul: verify Consul servers are up (`kubectl get pods -n consul`), check `CONSUL_HOST` in compose files.
- HAProxy has empty backends: confirm `CONSUL_DNS1/2/3` point to reachable VM agent DNS ports; ensure 8600/udp is exposed.
- Replication missing: check `patronictl list`; ensure VM IPs in `CONNECT_ADDRESS_VM*`/`RESTAPI_CONNECT_ADDRESS_VM*` are reachable from peers.

## Notes

- The bootstrap SQL runs only once on first cluster initialization. Subsequent restarts reuse the existing data directory and do not reapply the file.
- You can simulate a 3-node cluster on a single host by running `docker-compose -f docker-compose.vm{1,2,3}.yml up -d` with distinct ports already set.

## License

MIT
