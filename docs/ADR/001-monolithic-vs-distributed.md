# ADR 001: Monolithic Gen8 Deployment

**Status:** ✅ Accepted  
**Date:** 2025-11-06  
**Decider:** Dr. Samuel Hayden

## Context

Deploy transcript classification pipeline with constraints:
- Current volume: 200 transcripts/day
- Hardware: Gen8 (T4 16GB), prxmx2026 (L4 24GB)
- Timeline: KCNA exam November 14 (8 days)
- Budget: Unemployed, $680/mo child support

## Decision

**Deploy monolithic architecture on Gen8 T4 server.**

## Rationale

### L4 VRAM Constraint (Critical Finding)

| Model | Memory Required | L4 24GB? |
|-------|----------------|----------|
| Llama-3-8B (INT8) | 8GB | ✅ |
| Llama-3-70B (INT4) | 35GB + 9GB | ❌ |

**Conclusion:** L4 cannot run 70B models. Both hosts limited to 8B fallback → zero quality difference.

### Cost Analysis (90 Days)
```
Gen8 Monolithic:  $220
L4 Distributed:   $531
Savings:          $311 (58%)
```

### Time to Operational

- Gen8: 2 days
- Distributed: 4 days (PostgreSQL replication, networking)

## Consequences

**Positive:**
- ✅ Faster deployment (2 vs 4 days)
- ✅ $311 savings = 46% of monthly child support
- ✅ Single-host debugging
- ✅ Zero network dependency

**Negative:**
- ❌ No GPU specialization benefits
- ❌ Resume shows single-host (minor)

## Migration Trigger

Migrate to distributed if:
- Volume >2K docs/day (50% GPU utilization)
- Job with budget for 24/7 L4
- Real-time queries need <200ms

**Effort:** 8 hours (containers pre-built)

## References

- Claude conversation: Architecture analysis (2025-11-06)
