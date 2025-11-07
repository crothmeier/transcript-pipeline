# ADR 001: Monolithic Deployment Architecture

**Status:** ✅ Accepted  
**Date:** 2025-11-06  
**Author:** Dr. Samuel Hayden

## Context

Design decision for transcript classification pipeline deployment architecture with following constraints:

- **Current Volume:** 200 transcripts/day (~6K/month)
- **Available Hardware:** 
  - Gen8 Server: Tesla T4 16GB, 128GB RAM, 1.8TB RAID10
  - L4 Server: L4 24GB, 192GB RAM (primary LLM inference host)
- **Development Timeline:** 2-4 days to operational system
- **Operational Priority:** Simplicity and rapid deployment

## Decision

**Deploy monolithic architecture on Gen8 server with all services co-located.**

## Rationale

### GPU Memory Constraints

| Model | Memory Required (INT4) | L4 24GB Capable? | T4 16GB Capable? |
|-------|------------------------|------------------|------------------|
| Llama-3-8B | 8GB | ✅ Yes | ✅ Yes |
| Llama-3-13B | 13GB | ✅ Yes | ✅ Yes (tight) |
| Llama-3-70B | 44GB (35GB model + 9GB overhead) | ❌ No | ❌ No |

**Key Finding:** Neither available GPU supports 70B parameter models. Both systems limited to 8B/13B models for local inference, eliminating quality differentiation between distributed and monolithic architectures when using local LLM fallback.

### Performance Comparison

| Metric | Monolithic Gen8 | Distributed (Gen8 + L4) |
|--------|-----------------|------------------------|
| **Classification Speed** | 850ms (Claude API) | 850ms (same API) |
| **Embedding Speed** | 80ms (T4) | 80ms (same GPU) |
| **Total Throughput** | 95 docs/sec | 180 docs/sec |
| **Network Latency** | 0ms (localhost) | 0.3ms (10GbE) |
| **Deployment Complexity** | Low (single host) | High (2 hosts, networking) |
| **Time to Operational** | 2 days | 4 days |
| **Power Consumption** | 85W (Gen8 only) | 205W (Gen8 + L4) |

### Capacity Analysis

**Current Load:** 200 docs/day = 0.002 docs/sec  
**Gen8 Capacity:** 95 docs/sec  
**Utilization:** 0.002% (massive headroom)  

**Scaling Threshold:** Distributed architecture becomes necessary at ~2,000 docs/day (50% GPU utilization).

### Operational Considerations

**Monolithic Advantages:**
- ✅ Single host for all debugging and monitoring
- ✅ No network dependencies between services
- ✅ Simpler Docker Compose configuration
- ✅ Faster deployment (2 vs 4 days)
- ✅ Lower operational complexity

**Distributed Trade-offs:**
- ❌ Requires cross-host networking setup
- ❌ More complex service discovery
- ❌ Higher power consumption (58% increase)
- ❌ No quality benefit (same 8B fallback model)
- ❌ Marginal speed improvement (0.3ms network latency negligible)

## Infrastructure Details

**Storage:**
- Type: mdadm RAID10 (ext4 filesystem)
- Capacity: 1.8TB total, 1.1TB available
- Mount: `/mnt/raid10`
- Projected capacity: 6+ years at current volume

**Backup Strategy:**
- Daily PostgreSQL dumps via `pg_dump`
- 30-day retention with gzip compression
- rsync to `/mnt/raid10/proxmox-backup/transcripts`
- mdadm RAID monitoring for array health

## Consequences

### Positive

- **Rapid Deployment:** System operational in 2 days vs 4 days for distributed
- **Operational Simplicity:** Single-host debugging, no network troubleshooting
- **Cost Efficiency:** Lower power consumption (120W savings, 58% reduction)
- **Sufficient Capacity:** 47,500x current volume capacity

### Negative

- **No GPU Specialization:** Cannot leverage L4's superior inference performance (25% faster)
- **Single Point of Failure:** All services on one host
- **Limited Future Scale:** Must migrate at ~2K docs/day

### Mitigations

- **Containerized Design:** 8-hour migration path to distributed when volume justifies
- **Documented Architecture:** Portfolio demonstrates distributed design capability
- **Monitoring Alerts:** GPU utilization >50% triggers architecture review

## Migration Triggers

Reconsider distributed architecture when:

1. **Volume Threshold:** Daily transcripts exceed 2,000 (50% GPU utilization)
2. **Real-Time Requirements:** User-facing queries require <200ms p95 latency
3. **Availability Requirements:** Need for zero-downtime deployments
4. **Cost Justification:** API costs exceed $50/month (local inference ROI)

**Migration Effort Estimate:** 8 hours (containers pre-built, orchestration designed)

## Alternatives Considered

### Option A: Distributed (L4 + Gen8)
**Rejected:** No quality advantage (both limited to 8B models), higher complexity, slower deployment

### Option B: Monolithic on L4
**Rejected:** Requires PostgreSQL migration, loses Gen8 RAID10 storage, higher power consumption

### Option C: Hybrid (local classification, remote embeddings)
**Rejected:** Adds network dependency without throughput benefit at current scale

## Review Schedule

- **Monthly:** Review volume trends and GPU utilization metrics
- **Quarterly:** Evaluate API cost vs local inference trade-offs
- **On Trigger:** Immediate review if volume exceeds 2K docs/day

## References

- [GPU Memory Requirements Analysis](../work-logs/2025-11-06.md)
- [Performance Benchmarks](../benchmarks/inference-latency.md)
- [Claude Architecture Discussion](https://claude.ai/chat/xxxxx)

---

**Last Reviewed:** 2025-11-06  
**Next Review:** 2025-12-06
