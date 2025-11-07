# K3s Deployment Guide - Transcript Pipeline

Production-ready deployment of the AI transcript pipeline on K3s with PostgreSQL 16, pgvector extension, and GPU node affinity.

## Architecture Overview

- **Cluster**: K3s lightweight Kubernetes
- **Worker Node**: Gen8 server with Tesla T4 16GB GPU
- **Storage**: RAID10 array at `/mnt/raid10/transcript-pipeline/`
- **Database**: PostgreSQL 16 with pgvector, optimized for 128GB RAM
- **Namespace**: `transcript-pipeline`

## Prerequisites

### Required
- K3s cluster installed and running
- `kubectl` configured with cluster access
- Gen8 node with NVIDIA Tesla T4 GPU
- NVIDIA device plugin installed in K3s
- Storage path `/mnt/raid10/transcript-pipeline/` available on Gen8 node
- Minimum 100Gi available storage

### Verify Prerequisites

```bash
# Check K3s cluster access
kubectl version --short

# List available nodes
kubectl get nodes -o wide

# Verify NVIDIA device plugin (if GPU services planned)
kubectl get pods -n kube-system | grep nvidia

# Check available storage on Gen8 node
ssh gen8 "df -h /mnt/raid10/transcript-pipeline/"
```

## Quick Start

### Automated Deployment

```bash
cd /path/to/transcript-pipeline
./scripts/setup/04-deploy-k3s.sh
```

The script will:
1. Verify kubectl access
2. Prompt for Gen8 hostname
3. Update manifests with node affinity
4. Prompt for PostgreSQL password
5. Apply all Kubernetes manifests
6. Wait for PostgreSQL to be ready
7. Initialize database schema
8. Verify deployment

### Manual Deployment

If you prefer step-by-step control:

#### 1. Update Gen8 Hostname

Edit the following files and replace `GEN8_HOSTNAME` with your actual hostname:

```bash
# Find your Gen8 node hostname
kubectl get nodes -o wide

# Update manifests
sed -i 's/GEN8_HOSTNAME/your-gen8-hostname/g' manifests/k3s/04-postgres-pv.yaml
sed -i 's/GEN8_HOSTNAME/your-gen8-hostname/g' manifests/k3s/06-postgres-statefulset.yaml
```

#### 2. Set PostgreSQL Password

Edit `manifests/k3s/01-postgres-secret.yaml` and change `CHANGE_ME_BEFORE_DEPLOY`:

```yaml
stringData:
  POSTGRES_USER: "transcript_user"
  POSTGRES_DB: "transcripts_db"
  POSTGRES_PASSWORD: "your-strong-password-here"
```

**Security Best Practice**: For production, use external secret management:
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- K3s native secrets encryption

#### 3. Create Namespace

```bash
kubectl create namespace transcript-pipeline
```

#### 4. Apply Manifests

```bash
# Apply all resources using Kustomize
kubectl apply -k manifests/k3s/

# Verify resources
kubectl get all -n transcript-pipeline
```

#### 5. Wait for PostgreSQL

```bash
# Watch pod status
kubectl get pods -n transcript-pipeline -w

# Wait for ready state (Ctrl+C to exit watch after ready)
kubectl wait --for=condition=ready pod -l app=postgres -n transcript-pipeline --timeout=300s
```

#### 6. Initialize Database

```bash
# Run initialization job
kubectl apply -f manifests/k3s/08-init-db-job.yaml

# Wait for completion
kubectl wait --for=condition=complete job/postgres-init -n transcript-pipeline --timeout=180s

# Check logs
kubectl logs -n transcript-pipeline job/postgres-init
```

#### 7. Verify Deployment

```bash
# Check extensions are installed
kubectl exec -n transcript-pipeline postgres-0 -- \
  psql -U transcript_user -d transcripts_db -c '\dx'

# Expected output: uuid-ossp, pgvector, pg_trgm
```

## Configuration

### PostgreSQL Tuning

The deployment includes production-grade tuning in `02-postgres-config.yaml`:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `shared_buffers` | 32GB | 25% of system RAM |
| `effective_cache_size` | 96GB | 75% of system RAM |
| `work_mem` | 512MB | Large sorts/joins for vector ops |
| `maintenance_work_mem` | 2GB | Index creation optimization |
| `random_page_cost` | 1.1 | SSD RAID10 optimization |
| `max_connections` | 100 | Concurrent client limit |

### Resource Limits

PostgreSQL pod resources:

```yaml
requests:
  memory: 20Gi
  cpu: 4
limits:
  memory: 40Gi
  cpu: 8
```

### Storage

- **Type**: hostPath with DirectoryOrCreate
- **Path**: `/mnt/raid10/transcript-pipeline/pgdata`
- **Capacity**: 100Gi
- **Reclaim Policy**: Retain (data persists after PVC deletion)
- **Node Affinity**: Bound to Gen8 node

## Accessing the Database

### From Local Machine (Port Forward)

```bash
# Forward PostgreSQL port to localhost
kubectl port-forward -n transcript-pipeline svc/postgres 5432:5432

# Connect with psql
psql -h localhost -p 5432 -U transcript_user -d transcripts_db
```

### From Within Cluster

Service DNS: `postgres.transcript-pipeline.svc.cluster.local:5432`

Example connection from a pod:

```bash
kubectl run -it --rm psql-client --image=postgres:16 -n transcript-pipeline -- \
  psql -h postgres.transcript-pipeline.svc.cluster.local -U transcript_user -d transcripts_db
```

## Monitoring and Maintenance

### View Logs

```bash
# PostgreSQL logs
kubectl logs -n transcript-pipeline postgres-0 -f

# Init job logs
kubectl logs -n transcript-pipeline job/postgres-init

# All pod logs
kubectl logs -n transcript-pipeline --all-containers=true -l app=postgres
```

### Exec into Pod

```bash
kubectl exec -it -n transcript-pipeline postgres-0 -- bash
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pod -n transcript-pipeline

# Node resource usage
kubectl top node
```

### Backup Database

```bash
# Backup to local file
kubectl exec -n transcript-pipeline postgres-0 -- \
  pg_dump -U transcript_user -d transcripts_db > backup-$(date +%Y%m%d).sql

# Restore from backup
kubectl exec -i -n transcript-pipeline postgres-0 -- \
  psql -U transcript_user -d transcripts_db < backup-20250101.sql
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -n transcript-pipeline postgres-0

# Common issues:
# - Node selector doesn't match any node (check GEN8_HOSTNAME)
# - PV not binding (check hostPath exists on node)
# - Image pull errors (check network connectivity)
```

### Database Connection Refused

```bash
# Check if PostgreSQL is listening
kubectl exec -n transcript-pipeline postgres-0 -- pg_isready

# Check service endpoints
kubectl get endpoints -n transcript-pipeline postgres

# Verify secret is correct
kubectl get secret -n transcript-pipeline postgres-secret -o jsonpath='{.data}' | jq 'map_values(@base64d)'
```

### Init Job Failing

```bash
# Check job status
kubectl get jobs -n transcript-pipeline

# View job logs
kubectl logs -n transcript-pipeline job/postgres-init

# Common issues:
# - PostgreSQL not ready (wait longer)
# - Schema already exists (delete and retry)
# - pgvector not installed (check init container logs)
```

### Storage Issues

```bash
# Check PV/PVC status
kubectl get pv,pvc -n transcript-pipeline

# Check node storage
ssh gen8 "df -h /mnt/raid10/transcript-pipeline/"

# Check permissions
ssh gen8 "ls -la /mnt/raid10/transcript-pipeline/pgdata"
```

### Performance Issues

```bash
# Check query performance
kubectl exec -n transcript-pipeline postgres-0 -- \
  psql -U transcript_user -d transcripts_db -c \
  "SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Check active connections
kubectl exec -n transcript-pipeline postgres-0 -- \
  psql -U transcript_user -d transcripts_db -c \
  "SELECT count(*) FROM pg_stat_activity;"
```

## Scaling and High Availability

### Current Limitations

This deployment is configured for **single-node operation**:
- 1 replica StatefulSet
- hostPath storage (node-local)
- No automatic failover

### Future Enhancements

For production HA, consider:

1. **PostgreSQL Streaming Replication**
   - Add standby replicas
   - Configure synchronous replication
   - Use Patroni for automatic failover

2. **Distributed Storage**
   - Replace hostPath with Longhorn/Rook-Ceph
   - Enable multi-node access
   - Add snapshot capabilities

3. **Connection Pooling**
   - Deploy PgBouncer sidecar
   - Reduce connection overhead
   - Support higher concurrent load

## Cleanup

### Remove All Resources

```bash
# Delete entire namespace (including PVCs)
kubectl delete namespace transcript-pipeline

# Delete PV manually (due to Retain policy)
kubectl delete pv postgres-pv

# Clean up storage on node (CAUTION: destroys data)
ssh gen8 "sudo rm -rf /mnt/raid10/transcript-pipeline/pgdata"
```

### Remove Only Database Data

```bash
# Delete StatefulSet and Job
kubectl delete statefulset postgres -n transcript-pipeline
kubectl delete job postgres-init -n transcript-pipeline

# Optionally delete PVC to wipe data
kubectl delete pvc postgres-pvc -n transcript-pipeline
```

## Security Considerations

### Current Implementation

- Secrets stored as Kubernetes Secrets (base64 encoded)
- hostPath storage (root access on node)
- No TLS/SSL for database connections

### Production Hardening

1. **Enable TLS for PostgreSQL**
   - Generate SSL certificates
   - Mount certs as secrets
   - Configure `ssl=on` in postgresql.conf

2. **Use External Secret Management**
   - AWS Secrets Manager
   - HashiCorp Vault
   - Azure Key Vault

3. **Network Policies**
   - Restrict ingress to database pod
   - Allow only specific namespaces/pods

4. **RBAC**
   - Create service accounts with minimal permissions
   - Use pod security standards/policies

## Next Steps

After successful deployment:

1. **Deploy Application Services**
   - Transcription workers (GPU-enabled)
   - API server
   - Background job processors

2. **Configure Backups**
   - Set up automated pg_dump cron jobs
   - Store backups off-cluster
   - Test restore procedures

3. **Set Up Monitoring**
   - Prometheus metrics export
   - Grafana dashboards
   - Alerting rules

4. **Implement CI/CD**
   - GitOps with ArgoCD/Flux
   - Automated testing
   - Canary deployments

## References

- [K3s Documentation](https://docs.k3s.io/)
- [PostgreSQL 16 Documentation](https://www.postgresql.org/docs/16/)
- [pgvector Extension](https://github.com/pgvector/pgvector)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Kustomize](https://kustomize.io/)
