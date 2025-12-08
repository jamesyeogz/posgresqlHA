# PostgreSQL HA Cluster Setup Checklist

Use this checklist to verify your cluster is properly configured.

## Pre-Setup Checklist

### System Requirements

- [ ] Docker 20.10+ installed
- [ ] Docker Compose v2+ installed
- [ ] At least 4GB RAM available for Docker
- [ ] Required ports not in use (2379, 2380, 5432, 5000-5001, 7000, 8008)

### Network Requirements (Multi-VM)

- [ ] All VMs can reach each other on the network
- [ ] Firewall allows ports: 2379, 2380, 5432, 8008
- [ ] VM IP addresses are static or reserved via DHCP

## Configuration Checklist

### Environment Files

- [ ] `.env.vm1` created and configured
- [ ] `.env.vm2` created and configured  
- [ ] `.env.vm3` created and configured
- [ ] All NODE1_IP, NODE2_IP, NODE3_IP values match across all files
- [ ] POSTGRES_PASSWORD set to secure value
- [ ] REPLICATION_PASSWORD set to secure value

### HAProxy Configuration

- [ ] `haproxy/haproxy.cfg` updated with correct VM IPs
- [ ] IP addresses match NODE1_IP, NODE2_IP, NODE3_IP
- [ ] HAProxy stats credentials changed from defaults

## Deployment Checklist

### Development (Single Host)

- [ ] Run: `docker-compose -f docker-compose.dev.yml up -d`
- [ ] Wait 60 seconds for initialization
- [ ] Verify etcd cluster: `docker exec etcd1 etcdctl endpoint health --cluster`
- [ ] Verify Patroni cluster: `docker exec patroni1 patronictl list`
- [ ] Test primary connection: `psql -h localhost -p 5000 -U postgres`
- [ ] Test replica connection: `psql -h localhost -p 5001 -U postgres`
- [ ] Verify HAProxy stats: http://localhost:7000/stats

### Production (Multi-VM)

#### VM1
- [ ] Environment file configured: `.env.vm1`
- [ ] Run: `docker-compose --env-file .env.vm1 -f docker-compose.vm1.yml up -d`
- [ ] Verify etcd1 running: `docker logs etcd1`

#### VM2
- [ ] Environment file configured: `.env.vm2`
- [ ] Run: `docker-compose --env-file .env.vm2 -f docker-compose.vm2.yml up -d`
- [ ] Verify etcd2 running: `docker logs etcd2`

#### VM3
- [ ] Environment file configured: `.env.vm3`
- [ ] Run: `docker-compose --env-file .env.vm3 -f docker-compose.vm3.yml up -d`
- [ ] Verify etcd3 running: `docker logs etcd3`

#### Cluster Verification
- [ ] etcd cluster healthy: `docker exec etcd1 etcdctl endpoint health --cluster`
- [ ] etcd shows 3 members: `docker exec etcd1 etcdctl member list`
- [ ] Patroni cluster shows 1 Leader + 2 Replicas: `docker exec patroni1 patronictl list`
- [ ] Leader accepts writes: `psql -h <NODE_IP> -p 5432 -U postgres -c "CREATE TABLE test(id int);"`
- [ ] Replicas are synchronized: Check "Lag in MB" column in `patronictl list`

#### HAProxy Deployment
- [ ] Environment file configured: `.env.haproxy`
- [ ] `haproxy/haproxy.cfg` has correct IPs
- [ ] Run: `docker-compose --env-file .env.haproxy -f docker-compose.haproxy.yml up -d`
- [ ] Stats dashboard accessible: http://<HAPROXY_IP>:7000/stats
- [ ] All backends show UP in dashboard
- [ ] Primary endpoint works: `psql -h <HAPROXY_IP> -p 5000 -U postgres`
- [ ] Replica endpoint works: `psql -h <HAPROXY_IP> -p 5001 -U postgres`

## Post-Setup Verification

### Cluster Health

```bash
# etcd cluster health (all 3 should be healthy)
docker exec etcd1 etcdctl endpoint health --cluster

# Patroni cluster status (1 Leader, 2 Replicas)
docker exec patroni1 patronictl list

# PostgreSQL connectivity
psql -h localhost -p 5000 -U postgres -c "SELECT version();"
```

### Replication

```bash
# On primary - check replication status
docker exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Should show 2 streaming replicas
```

### Failover Test

```bash
# 1. Note current leader
docker exec patroni1 patronictl list

# 2. Stop the leader
docker stop patroni1

# 3. Wait 30-60 seconds

# 4. Verify new leader elected
docker exec patroni2 patronictl list

# 5. Restart original node
docker start patroni1

# 6. Verify it rejoins as replica
docker exec patroni1 patronictl list
```

## Troubleshooting Checklist

### etcd Not Forming Cluster

- [ ] Check all 3 nodes started within 60 seconds
- [ ] Verify IP addresses are correct in all .env files
- [ ] Check firewall allows ports 2379 and 2380
- [ ] Check etcd logs: `docker logs etcd1`
- [ ] Test connectivity: `docker exec etcd1 nc -zv <NODE2_IP> 2380`

### Patroni Not Electing Leader

- [ ] Verify etcd cluster is healthy first
- [ ] Check PATRONI_ETCD3_HOSTS has correct IPs
- [ ] Check Patroni logs: `docker logs patroni1`
- [ ] Test etcd connectivity: `docker exec patroni1 curl http://etcd1:2379/health`

### HAProxy Shows Backends DOWN

- [ ] Verify Patroni API is accessible: `curl http://<NODE_IP>:8008/health`
- [ ] Check IP addresses in haproxy.cfg match actual VM IPs
- [ ] Check HAProxy logs: `docker logs haproxy`
- [ ] Verify firewall allows port 8008

### Connection Refused

- [ ] Check PostgreSQL is ready: `docker exec patroni1 pg_isready`
- [ ] Verify credentials are correct
- [ ] Check pg_hba.conf allows connections

## Security Checklist (Production)

- [ ] Changed POSTGRES_PASSWORD from default
- [ ] Changed REPLICATION_PASSWORD from default
- [ ] Changed HAProxy stats password (admin/admin123)
- [ ] Configured firewall rules
- [ ] Using private network for cluster communication
- [ ] Enabled PostgreSQL connection logging
- [ ] Set up monitoring and alerting
- [ ] Configured backup strategy
