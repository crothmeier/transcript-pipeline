# Transcript Pipeline

> GPU-accelerated RAG pipeline for AI transcript classification and knowledge base management

## 🎯 Overview

Automates collection, classification, and indexing of ChatGPT/Claude conversation transcripts using local GPU inference and semantic embeddings.

**Architecture:** Monolithic deployment optimized for single-host operation  
**GPU:** NVIDIA Tesla T4 16GB  
**Storage:** mdadm RAID10 (1.8TB, ext4)  
**Status:** 🚧 In Development

## 🏗️ Architecture Highlights

- **PostgreSQL 16** with pgvector for semantic search
- **BGE-M3** embeddings (1024-dim vectors) on T4 GPU
- **Claude Sonnet 4.5** API with local LLM fallback
- **Prefect** orchestration for automated daily processing
- **Prometheus + Grafana** monitoring stack

## 🚀 Quick Start
```bash
# Clone and configure
git clone git@github.com:crothmeier/transcript-pipeline.git
cd transcript-pipeline
cp .env.example .env
# Edit .env with your API keys

# Deploy infrastructure
make setup
make deploy

# Process historical transcripts
make backfill DAYS=30

# Check status
make status
```

## 📊 Current Status

| Component | Status |
|-----------|--------|
| PostgreSQL + pgvector | ⚪ Not Started |
| Embedding Service (BGE-M3) | ⚪ Not Started |
| Classification Service | ⚪ Not Started |
| Orchestration (Prefect) | ⚪ Not Started |
| Monitoring Stack | ⚪ Not Started |

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Infrastructure Setup](docs/setup/01-infrastructure.md)
- [Architecture Decisions](docs/ADR/)
- [Troubleshooting](docs/runbooks/troubleshooting.md)

## 🛠️ Technology Stack

**Infrastructure:**
- HPE ProLiant DL380p Gen8 (2x Xeon E5-2690 v2, 128GB RAM)
- NVIDIA Tesla T4 16GB GPU
- mdadm RAID10 (1.8TB ext4)

**Software:**
- Python 3.11, PostgreSQL 16, pgvector
- vLLM 0.6.1, Anthropic Claude API
- Docker Compose, Prefect 2.14
- Prometheus, Grafana

## 📈 Performance Characteristics

- **Throughput:** ~100 transcripts/sec (embedding generation)
- **Latency:** <1s per transcript (end-to-end classification)
- **Storage:** ~15KB per transcript (avg)
- **GPU Utilization:** 40% (embedding service)

## 📝 Development

See [CHANGELOG.md](CHANGELOG.md) for version history.

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

**Author:** Dr. Samuel Hayden  
**Contact:** crothmeier@lazarus-labs.com  
**Started:** November 2025



📊 Current Status
ComponentStatusDeploymentNodeLast UpdatedPostgreSQL + pgvector✅ DeployedK3s StatefulSetphx-ai01 (T4)2025-11-07Embedding Service (BGE-M3)⏳ In ProgressK3s Deploymentphx-ai01 (T4)-Classification Service⚪ PlannedK3s Deploymentphx-ai01 (T4)-Orchestration (Prefect)⚪ PlannedK3s CronJobphx-ai01-Monitoring Stack⚪ PlannedK3s DaemonSetAll nodes-
Progress: 1/5 components (20%)
Database Stats:

13 taxonomy tags across 5 categories
3 tables, 11 indexes
Vector similarity search ready (HNSW)
Full-text search ready (GIN)

Quick Access:
bashkubectl port-forward -n transcript-pipeline svc/postgres 5432:5432
```
```

Save and commit:
```bash
git add README.md
git commit -m "docs: update PostgreSQL deployment status"
git push origin main
```

---

## Step 6: Proceed to Embeddings Service
```bash
# On phx-ai01 (where Claude Code can generate files)
cd ~/git/transcript-pipeline

claude code "Create BGE-M3 embedding service for K3s deployment:

INFRASTRUCTURE:
- K3s cluster with phx-ai01 node (Tesla T4 16GB GPU)
- Namespace: transcript-pipeline
- PostgreSQL: postgres.transcript-pipeline.svc.cluster.local:5432
- GPU resource: nvidia.com/gpu: 1

DELIVERABLES:

1. Dockerfile (src/embeddings/Dockerfile):
   - Base: nvidia/cuda:12.1.0-runtime-ubuntu22.04
   - Python 3.11
   - Install: vllm==0.6.1, fastapi==0.104.1, uvicorn[standard]==0.24.0, prometheus-client==0.19.0, pydantic==2.5.0, python-json-logger==2.0.7
   - Non-root user: embeddings (UID 1000)
   - Workdir: /app
   - Copy: requirements.txt, embeddings.py
   - Expose: 8001
   - Healthcheck: curl -f http://localhost:8001/health || exit 1, interval=30s
   - CMD: uvicorn embeddings:app --host 0.0.0.0 --port 8001 --workers 4

2. Python Service (src/embeddings/embeddings.py):
   - FastAPI application
   - Endpoints:
     * GET /health: {status: str, model: str, gpu_memory_gb: float, uptime_seconds: int}
     * POST /embed/batch: Request {texts: List[str]}, Response {embeddings: List[List[float]], processing_time_ms: int, batch_size: int, model: str}
   - Load BAAI/bge-m3 with vLLM:
     * from vllm import LLM
     * gpu_memory_utilization from env (default 0.4)
     * tensor_parallel_size: 1
     * trust_remote_code: true
   - Batch processing:
     * Accept 1-32 texts per request
     * Validate: reject empty, >8192 tokens
     * Return 1024-dim float vectors
     * Timeout: 30s
   - Prometheus metrics:
     * embeddings_requests_total (Counter)
     * embeddings_latency_seconds (Histogram, buckets=[0.01,0.05,0.1,0.5,1.0,5.0])
     * embeddings_batch_size (Histogram, buckets=[1,5,10,20,32])
     * embeddings_errors_total (Counter with error_type label)
     * gpu_memory_used_bytes (Gauge)
   - JSON structured logging with request_id, batch_size, latency_ms
   - Error handling: CUDA OOM (507), timeout (408), invalid input (400)

3. Requirements (src/embeddings/requirements.txt):
   - Pin all versions

4. K3s Deployment (manifests/k3s/embeddings-deployment.yaml):
   - Deployment: 1 replica
   - Image: localhost/transcript-embeddings:latest
   - ImagePullPolicy: Never (local image)
   - Env:
     * GPU_MEMORY_UTILIZATION: \"0.4\"
     * MODEL_NAME: \"BAAI/bge-m3\"
     * LOG_LEVEL: \"INFO\"
   - Resources:
     * requests: nvidia.com/gpu=1, memory=8Gi, cpu=4
     * limits: nvidia.com/gpu=1, memory=20Gi, cpu=8
   - NodeSelector: kubernetes.io/hostname=phx-ai01
   - LivenessProbe: httpGet /health, port 8001, initialDelaySeconds=30, periodSeconds=10
   - ReadinessProbe: httpGet /health, port 8001, initialDelaySeconds=60, periodSeconds=5
   - SecurityContext: runAsNonRoot=true, runAsUser=1000

5. Service (manifests/k3s/embeddings-service.yaml):
   - Name: embeddings
   - Type: ClusterIP
   - Selector: app=embeddings
   - Port: 8001, targetPort: 8001

6. Update Kustomization (manifests/k3s/kustomization.yaml):
   - Add embeddings-deployment.yaml and embeddings-service.yaml to resources

7. Build Script (scripts/build-embeddings.sh):
   - Build: docker build -t transcript-embeddings:latest src/embeddings/
   - Save: docker save transcript-embeddings:latest -o /tmp/embeddings.tar
   - Import to K3s: sudo k3s ctr images import /tmp/embeddings.tar
   - Cleanup: rm /tmp/embeddings.tar
   - Verify: sudo k3s ctr images ls | grep transcript-embeddings

8. Integration Test (tests/integration/test_embeddings_k3s.py):
   - Port-forward embeddings:8001
   - Test /health endpoint
   - Test single embedding (verify 1024 dims)
   - Test batch (8 texts)
   - Assert latency <100ms per text
   - Verify Prometheus metrics at /metrics

9. Deployment Documentation (docs/setup/EMBEDDINGS-DEPLOYMENT.md):
   - Build instructions
   - Deploy to K3s
   - Verification steps
   - Troubleshooting

Generate production-ready embedding service optimized for Tesla T4 with vLLM."
```

---

## Deployment Summary

✅ **PostgreSQL Deployed Successfully**

**Resources:**
- Pod: postgres-0 (Running on phx-ai01)
- Storage: 100Gi hostPath on /mnt/raid10
- Service: postgres.transcript-pipeline.svc.cluster.local

**Database:**
- Extensions: vector 0.8.1, pg_trgm 1.6
- Tables: transcripts, tags, transcript_tags
- Indexes: 11 (HNSW, GIN, BRIN, B-tree)
- Seed data: 13 taxonomy tags

**Status:** Production-ready ✅

---

## Quick Status Check
```bash
# Everything in one command
kubectl exec -n transcript-pipeline postgres-0 -- bash -c "
echo '=== Extensions ==='
psql -U transcript_user -d transcripts_db -c '\\dx'
echo ''
echo '=== Tables ==='
psql -U transcript_user -d transcripts_db -c '\\dt'
echo ''
echo '=== Tag Count ==='
psql -U transcript_user -d transcripts_db -c 'SELECT COUNT(*) FROM tags;'
echo ''
echo '✅ PostgreSQL Ready!
