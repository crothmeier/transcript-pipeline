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
