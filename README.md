# Transcript Pipeline

> GPU-accelerated RAG pipeline for AI transcript classification and knowledge base management

## 🎯 Overview

Automates collection, classification, and indexing of ChatGPT/Claude conversation transcripts using local GPU inference.

**Architecture:** Monolithic on HPE ProLiant DL380p Gen8  
**GPU:** NVIDIA Tesla T4 16GB  
**Storage:** ZFS RAID10 (1.7TB)  
**Status:** 🚧 In Development

## 🚀 Quick Start
```bash
# Clone and setup
git clone git@github.com:crothmeier/transcript-pipeline.git
cd transcript-pipeline
cp .env.example .env

# Deploy
make setup
make deploy
```

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Setup Guide](docs/setup/01-infrastructure.md)
- [Architecture Decisions](docs/ADR/)

## 🛠️ Stack

- Python 3.11, PostgreSQL 16, pgvector
- vLLM, Anthropic Claude API, BGE-M3
- Docker Compose, Prefect
- Prometheus, Grafana

## 📝 Development

See [CHANGELOG.md](CHANGELOG.md) for project history.

---

**Maintainer:** Dr. Samuel Hayden  
**Started:** 2025-11-06
