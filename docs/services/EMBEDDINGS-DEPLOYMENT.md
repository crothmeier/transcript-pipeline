# BGE-M3 Embedding Service Deployment Guide

Production deployment guide for the BGE-M3 embedding service on K3s with Tesla T4 GPU.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Build Instructions](#build-instructions)
- [Deployment Instructions](#deployment-instructions)
- [API Reference](#api-reference)
- [Performance Characteristics](#performance-characteristics)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

### Components

- **Model**: BAAI/bge-m3 - Multilingual embedding model producing 1024-dimensional vectors
- **Inference Engine**: vLLM 0.6.1 - GPU-accelerated inference with optimized batching
- **API Framework**: FastAPI 0.104.1 - High-performance async HTTP API
- **Runtime**: CUDA 12.1.0 on Ubuntu 22.04 with Python 3.11

### Infrastructure

- **K3s Cluster**: Lightweight Kubernetes distribution
- **GPU Node**: phx-ai01 with NVIDIA Tesla T4 (16GB VRAM)
- **Namespace**: transcript-pipeline
- **Service Type**: ClusterIP (internal access only)
- **Resource Allocation**:
  - GPU: 1x Tesla T4 (40% memory utilization)
  - CPU: 4-8 cores
  - RAM: 8-20 GB

### Key Features

- **Batch Processing**: 1-32 texts per request with automatic batching
- **GPU Optimization**: Configurable GPU memory utilization (default 40%)
- **Structured Logging**: JSON logs for observability
- **Prometheus Metrics**: Request counts, latency histograms, GPU memory usage
- **Health Checks**: Liveness and readiness probes with GPU status
- **Error Handling**: Comprehensive error responses for OOM, timeouts, validation

## Prerequisites

### System Requirements

1. **Docker** (version 20.10+)
   ```bash
   docker --version
   ```

2. **K3s Access** with kubectl configured
   ```bash
   kubectl version
   kubectl get nodes
   ```

3. **GPU Node** with NVIDIA drivers and device plugin
   ```bash
   kubectl get nodes -o json | jq '.items[].status.allocatable."nvidia.com/gpu"'
   ```

4. **Permissions**: sudo access for K3s image import

### Verify GPU Availability

```bash
# Check GPU node
kubectl get nodes -l kubernetes.io/hostname=phx-ai01

# Verify GPU resources
kubectl describe node phx-ai01 | grep nvidia.com/gpu

# Check for any existing GPU workloads
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[].resources.requests."nvidia.com/gpu" != null)'
```

## Build Instructions

### 1. Build Docker Image

The build script handles Docker image creation and K3s import:

```bash
./scripts/build-embeddings.sh
```

This script performs:
1. Builds Docker image from `src/embeddings/Dockerfile`
2. Saves image to tarball
3. Imports into K3s using `k3s ctr`
4. Verifies import
5. Cleans up temporary files

### 2. Manual Build (Alternative)

```bash
# Navigate to repo root
cd /path/to/transcript-pipeline

# Build image
docker build -t transcript-embeddings:latest \
  -f src/embeddings/Dockerfile \
  src/embeddings/

# Save and import to K3s
docker save transcript-embeddings:latest -o /tmp/embeddings.tar
sudo k3s ctr images import /tmp/embeddings.tar
rm /tmp/embeddings.tar

# Verify
sudo k3s ctr images ls | grep transcript-embeddings
```

## Deployment Instructions

### 1. Deploy to K3s

The deployment script handles K3s resource creation and validation:

```bash
./scripts/deploy-embeddings.sh
```

This script performs:
1. Verifies image exists in K3s
2. Applies deployment and service manifests
3. Waits for pod readiness (up to 5 minutes)
4. Tests health endpoint
5. Displays connection information

### 2. Manual Deployment (Alternative)

```bash
# Apply manifests
kubectl apply -f manifests/k3s/09-embeddings-deployment.yaml
kubectl apply -f manifests/k3s/10-embeddings-service.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \
  -l app=embeddings \
  -n transcript-pipeline \
  --timeout=300s

# Check status
kubectl get pods -n transcript-pipeline -l app=embeddings
```

### 3. Verify Deployment

```bash
# Check pod status
kubectl get pods -n transcript-pipeline -l app=embeddings

# View logs
kubectl logs -n transcript-pipeline -l app=embeddings -f

# Test health endpoint
POD_NAME=$(kubectl get pods -n transcript-pipeline -l app=embeddings -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n transcript-pipeline $POD_NAME -- curl -s http://localhost:8001/health | jq
```

## API Reference

### Base URL

Internal cluster access:
```
http://embeddings.transcript-pipeline.svc.cluster.local:8001
```

### Endpoints

#### Health Check

**GET** `/health`

Returns service health and GPU status.

**Response:**
```json
{
  "status": "healthy",
  "model": "BAAI/bge-m3",
  "gpu_memory_gb": 4.52,
  "uptime_seconds": 1234
}
```

**Example:**
```bash
curl http://embeddings.transcript-pipeline.svc.cluster.local:8001/health
```

#### Batch Embedding

**POST** `/embed/batch`

Generate embeddings for 1-32 texts.

**Request Body:**
```json
{
  "texts": [
    "First text to embed",
    "Second text to embed"
  ]
}
```

**Response:**
```json
{
  "embeddings": [
    [0.123, -0.456, ...],  // 1024 dimensions
    [0.789, -0.012, ...]
  ],
  "processing_time_ms": 45,
  "batch_size": 2,
  "model": "BAAI/bge-m3"
}
```

**Validation Rules:**
- `texts` must contain 1-32 items
- Each text must be non-empty
- Each text must be ≤8192 tokens (~32,768 characters)

**Example:**
```bash
curl -X POST http://embeddings.transcript-pipeline.svc.cluster.local:8001/embed/batch \
  -H 'Content-Type: application/json' \
  -d '{
    "texts": [
      "Natural language processing with transformers",
      "GPU-accelerated machine learning inference"
    ]
  }' | jq
```

**Error Responses:**

```json
// 400 - Validation Error
{
  "error": "validation_error",
  "message": "text at index 0 is empty"
}

// 408 - Request Timeout
{
  "error": "request_timeout",
  "message": "Request processing timed out",
  "batch_size": 32
}

// 507 - Insufficient GPU Memory
{
  "error": "insufficient_gpu_memory",
  "message": "GPU out of memory. Try reducing batch size.",
  "batch_size": 32
}
```

#### Prometheus Metrics

**GET** `/metrics`

Returns Prometheus-formatted metrics.

**Example:**
```bash
curl http://embeddings.transcript-pipeline.svc.cluster.local:8001/metrics
```

## Performance Characteristics

### Tesla T4 GPU Benchmarks

Based on typical workloads:

| Batch Size | Latency (ms) | Throughput (texts/sec) |
|------------|--------------|------------------------|
| 1          | 20-40        | 25-50                  |
| 8          | 80-120       | 65-100                 |
| 16         | 140-200      | 80-115                 |
| 32         | 250-350      | 90-130                 |

### Resource Usage

- **GPU Memory**: ~6-8 GB (model + cache)
- **System Memory**: ~4-6 GB
- **CPU**: 2-4 cores actively used
- **Model Load Time**: 30-60 seconds (first startup)

### Optimization Tips

1. **Batch Size**: Use batches of 8-16 for optimal throughput
2. **GPU Memory**: Adjust `GPU_MEMORY_UTILIZATION` env var (0.4-0.9)
3. **Concurrent Requests**: vLLM handles batching automatically
4. **Text Length**: Shorter texts process faster

## Monitoring

### Prometheus Metrics

The service exposes the following metrics on `/metrics`:

#### Request Metrics

```
# Total number of embedding requests
embeddings_requests_total

# Request latency histogram (seconds)
embeddings_latency_seconds_bucket{le="0.01"}
embeddings_latency_seconds_bucket{le="0.05"}
embeddings_latency_seconds_bucket{le="0.1"}
embeddings_latency_seconds_bucket{le="0.5"}
embeddings_latency_seconds_bucket{le="1.0"}
embeddings_latency_seconds_bucket{le="5.0"}

# Batch size histogram
embeddings_batch_size_bucket{le="1"}
embeddings_batch_size_bucket{le="5"}
embeddings_batch_size_bucket{le="10"}
embeddings_batch_size_bucket{le="20"}
embeddings_batch_size_bucket{le="32"}

# Error counter by type
embeddings_errors_total{error_type="cuda_oom"}
embeddings_errors_total{error_type="timeout"}
embeddings_errors_total{error_type="validation_error"}
embeddings_errors_total{error_type="processing_error"}

# GPU memory usage (bytes)
gpu_memory_used_bytes
```

### Grafana Dashboards

Example PromQL queries:

```promql
# Request rate (requests per second)
rate(embeddings_requests_total[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(embeddings_latency_seconds_bucket[5m]))

# Average batch size
rate(embeddings_batch_size_sum[5m]) / rate(embeddings_batch_size_count[5m])

# Error rate
rate(embeddings_errors_total[5m])

# GPU memory usage (GB)
gpu_memory_used_bytes / 1024 / 1024 / 1024
```

### Logging

Logs are structured JSON for easy parsing:

```bash
# View recent logs
kubectl logs -n transcript-pipeline -l app=embeddings --tail=100

# Follow logs
kubectl logs -n transcript-pipeline -l app=embeddings -f

# Filter for errors
kubectl logs -n transcript-pipeline -l app=embeddings | grep '"level":"ERROR"'

# Parse JSON logs
kubectl logs -n transcript-pipeline -l app=embeddings | jq 'select(.level=="INFO")'
```

## Troubleshooting

### Pod Not Scheduling

**Symptom:** Pod stuck in `Pending` state

**Check:**
```bash
kubectl describe pod -n transcript-pipeline -l app=embeddings
```

**Common Causes:**

1. **No GPU available**
   ```bash
   kubectl get nodes -o json | jq '.items[].status.allocatable."nvidia.com/gpu"'
   ```
   Solution: Verify GPU node is available and not fully utilized

2. **Node selector mismatch**
   ```bash
   kubectl get nodes --show-labels | grep phx-ai01
   ```
   Solution: Verify node has correct hostname

3. **Image not found**
   ```bash
   sudo k3s ctr images ls | grep transcript-embeddings
   ```
   Solution: Run `./scripts/build-embeddings.sh`

### Out of Memory (OOM)

**Symptom:** Pod crashes with exit code 137 or CUDA OOM errors

**Check logs:**
```bash
kubectl logs -n transcript-pipeline -l app=embeddings --previous
```

**Solutions:**

1. **Reduce GPU memory utilization**
   Edit deployment:
   ```yaml
   env:
   - name: GPU_MEMORY_UTILIZATION
     value: "0.3"  # Reduce from 0.4
   ```

2. **Reduce batch size** in client requests (use smaller batches)

3. **Increase memory limits**
   ```yaml
   resources:
     limits:
       memory: "24Gi"  # Increase from 20Gi
   ```

### Model Download Failures

**Symptom:** Pod fails to start, logs show download errors

**Check logs:**
```bash
kubectl logs -n transcript-pipeline -l app=embeddings
```

**Solutions:**

1. **Network connectivity**
   ```bash
   kubectl exec -n transcript-pipeline $POD_NAME -- curl -I https://huggingface.co
   ```

2. **Increase startup timeout**
   ```yaml
   readinessProbe:
     initialDelaySeconds: 120  # Increase from 60
   ```

3. **Pre-download model** (mount as volume)

### Slow Inference

**Symptom:** High latency (>1s per request)

**Check metrics:**
```bash
kubectl port-forward -n transcript-pipeline svc/embeddings 8001:8001
curl http://localhost:8001/metrics | grep latency
```

**Solutions:**

1. **Check GPU utilization**
   ```bash
   kubectl exec -n transcript-pipeline $POD_NAME -- nvidia-smi
   ```

2. **Increase GPU memory utilization**
   ```yaml
   env:
   - name: GPU_MEMORY_UTILIZATION
     value: "0.6"  # Increase from 0.4
   ```

3. **Reduce CPU throttling**
   ```yaml
   resources:
     requests:
       cpu: "6"  # Increase from 4
   ```

### Service Unavailable

**Symptom:** Health check returns 503

**Check:**
```bash
# Pod status
kubectl get pods -n transcript-pipeline -l app=embeddings

# Readiness
kubectl get pods -n transcript-pipeline -l app=embeddings -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")]}'

# Recent events
kubectl get events -n transcript-pipeline --sort-by='.lastTimestamp' | tail -20
```

**Solutions:**

1. **Wait for model loading** (can take 30-60s)

2. **Check pod logs** for errors
   ```bash
   kubectl logs -n transcript-pipeline -l app=embeddings --tail=50
   ```

3. **Restart deployment**
   ```bash
   kubectl rollout restart deployment/embeddings -n transcript-pipeline
   ```

### Testing Connectivity

```bash
# Port forward for local testing
kubectl port-forward -n transcript-pipeline svc/embeddings 8001:8001

# Test health
curl http://localhost:8001/health | jq

# Test embedding
curl -X POST http://localhost:8001/embed/batch \
  -H 'Content-Type: application/json' \
  -d '{"texts": ["test"]}' | jq

# Check metrics
curl http://localhost:8001/metrics
```

## Integration Testing

Run the integration test suite:

```bash
# Ensure service is deployed
kubectl get pods -n transcript-pipeline -l app=embeddings

# Run tests
cd /path/to/transcript-pipeline
python -m pytest tests/integration/test_embeddings_k3s.py -v

# Run specific test
python -m pytest tests/integration/test_embeddings_k3s.py::TestEmbeddingsHealth -v
```

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GPU_MEMORY_UTILIZATION` | `0.4` | GPU memory fraction (0.0-1.0) |
| `MODEL_NAME` | `BAAI/bge-m3` | HuggingFace model identifier |
| `LOG_LEVEL` | `INFO` | Logging level (DEBUG/INFO/WARNING/ERROR) |
| `CUDA_VISIBLE_DEVICES` | `0` | GPU device ID |

### Resource Limits

Configured in `manifests/k3s/09-embeddings-deployment.yaml`:

```yaml
resources:
  requests:
    nvidia.com/gpu: "1"
    memory: "8Gi"
    cpu: "4"
  limits:
    nvidia.com/gpu: "1"
    memory: "20Gi"
    cpu: "8"
```

## Additional Resources

- [vLLM Documentation](https://docs.vllm.ai/)
- [BGE-M3 Model Card](https://huggingface.co/BAAI/bge-m3)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [K3s GPU Support](https://docs.k3s.io/advanced#nvidia-container-runtime-support)

## Support

For issues or questions:

1. Check logs: `kubectl logs -n transcript-pipeline -l app=embeddings`
2. Review this troubleshooting guide
3. Check Prometheus metrics for anomalies
4. Verify GPU node health: `kubectl describe node phx-ai01`
