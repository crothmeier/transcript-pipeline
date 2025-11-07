# Changelog

All notable changes documented here.

## [Unreleased]

### Planning
- PostgreSQL deployment with pgvector
- BGE-M3 embedding service
- Claude API classification service

## [0.1.0] - 2025-11-06

### Added
- Initial repository structure
- Documentation framework
- Architecture Decision Records

### Infrastructure
- Target: HPE ProLiant DL380p Gen8
  - CPU: 2x Xeon E5-2690 v2
  - RAM: 128GB DDR4 ECC
  - GPU: Tesla T4 16GB
  - Storage: ZFS RAID10 1.7TB

### Decisions
- ADR-001: Monolithic deployment on Gen8
  - Cost savings: $311 over 90 days
  - Time to operational: 2 days vs 4 days
