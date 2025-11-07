# PostgreSQL Deployment Guide - AI Transcript Pipeline

Production-grade PostgreSQL 16 deployment with pgvector for semantic search, optimized for 128GB RAM system with RAID10 storage.

## System Requirements

- **Storage**: mdadm RAID10 mounted at `/mnt/raid10` (ext4)
- **RAM**: 128GB (32GB allocated to PostgreSQL shared buffers)
- **GPU**: Tesla T4 16GB (for future pgvector acceleration)
- **OS**: Linux with Docker and Docker Compose
- **Backup**: Standard Linux tools (mdadm, pg_dump, rsync)

## Architecture Overview

### Database Schema

**transcripts** table:
- Vector embeddings (1024 dimensions) for semantic similarity search
- Full-text search on raw content
- JSONB metadata for flexible attributes
- Time-series optimization with BRIN indexes

**tags** table:
- Hierarchical taxonomy with parent-child relationships
- Mapped to Obsidian folder structure

**transcript_tags** junction table:
- Many-to-many relationships with AI confidence scores
- Track model provenance (assigned_by field)

### Performance Tuning

Optimized for write-heavy workloads with frequent vector similarity searches:
- `shared_buffers`: 32GB (25% of RAM)
- `effective_cache_size`: 96GB (kernel + PG cache)
- `work_mem`: 512MB (per-connection sort/hash operations)
- `random_page_cost`: 1.1 (SSD optimization)
- HNSW vector index: m=16, ef_construction=64

## Deployment Steps

### 1. Configure Storage

Run the storage configuration script to create directories and set permissions:

```bash
./scripts/setup/02-configure-storage.sh
```

This script:
- Verifies RAID10 mount at `/mnt/raid10`
- Checks mdadm RAID health
- Creates directory structure:
  - `/mnt/raid10/transcript-pipeline/pgdata` (PostgreSQL data)
  - `/mnt/raid10/transcript-pipeline/raw` (raw transcript files)
  - `/mnt/raid10/proxmox-backup/transcripts` (backups)
- Sets ownership to postgres UID 999

### 2. Configure Database Credentials

Create `.env` file from template:

```bash
cp .env.example .env
```

Edit `.env` and set secure password:

```bash
POSTGRES_DB=transcripts
POSTGRES_USER=transcript_admin
POSTGRES_PASSWORD=<generate-strong-password>
```

Generate strong password:
```bash
openssl rand -base64 32
```

### 3. Start PostgreSQL Container

Launch PostgreSQL 16 with pgvector:

```bash
docker-compose -f manifests/docker-compose.gen8.yml up -d
```

Monitor startup:
```bash
docker logs -f transcript-pipeline-postgres
```

### 4. Initialize Database

Run initialization script to install extensions and load schema:

```bash
./scripts/setup/03-init-database.sh
```

This script:
- Waits for PostgreSQL to be ready
- Verifies extensions: uuid-ossp, pgvector, pg_trgm
- Confirms schema creation (transcripts, tags, transcript_tags)
- Loads seed taxonomy data
- Displays connection information

### 5. Configure Automated Backups

Create daily backup cron job:

```bash
crontab -e
```

Add entry for daily 2 AM backup:
```cron
0 2 * * * /home/crathmene/git/transcript-pipeline/scripts/maintenance/backup-database.sh >> /var/log/transcript-backup.log 2>&1
```

Test backup script manually:
```bash
./scripts/maintenance/backup-database.sh
```

Backup features:
- Custom format with compression (level 9)
- 30-day retention policy
- RAID health verification before backup
- Return codes: 0=success, 1=dump failed, 2=raid degraded

## Database Connection

### Connection String

```
postgresql://transcript_admin:<password>@localhost:5432/transcripts
```

### Interactive psql Session

```bash
docker exec -it transcript-pipeline-postgres psql -U transcript_admin -d transcripts
```

### Example Queries

**Insert transcript with embedding:**
```sql
INSERT INTO transcripts (source, raw_content, summary, filepath, embedding, embedding_model, processed_at)
VALUES (
    'video_001.mp4',
    'Full transcript text here...',
    'AI-generated summary',
    '/mnt/raid10/transcript-pipeline/raw/video_001.mp4',
    '[0.1, 0.2, ..., 0.5]',  -- 1024-dim vector
    'text-embedding-3-large',
    NOW()
);
```

**Vector similarity search:**
```sql
SELECT id, source, summary, 1 - (embedding <=> query_embedding) AS similarity
FROM transcripts
ORDER BY embedding <=> '[0.1, 0.2, ..., 0.5]'::vector
LIMIT 10;
```

**Full-text search:**
```sql
SELECT id, source, ts_rank(to_tsvector('english', raw_content), query) AS rank
FROM transcripts, to_tsquery('english', 'kubernetes & troubleshooting') query
WHERE to_tsvector('english', raw_content) @@ query
ORDER BY rank DESC;
```

**Tag transcripts with confidence:**
```sql
INSERT INTO transcript_tags (transcript_id, tag_id, confidence, assigned_by)
VALUES (
    'uuid-of-transcript',
    (SELECT id FROM tags WHERE name = 'kubernetes/troubleshooting'),
    0.92,
    'gpt-4-classification-model'
);
```

## Maintenance

### Monitor Database Size

```bash
docker exec transcript-pipeline-postgres psql -U transcript_admin -d transcripts -c "
SELECT
    pg_size_pretty(pg_database_size('transcripts')) AS db_size,
    (SELECT COUNT(*) FROM transcripts) AS transcript_count,
    (SELECT COUNT(*) FROM tags) AS tag_count;
"
```

### Vacuum and Analyze

Run weekly maintenance:
```bash
docker exec transcript-pipeline-postgres psql -U transcript_admin -d transcripts -c "VACUUM ANALYZE;"
```

### Monitor RAID Health

```bash
sudo mdadm --detail /dev/md0
```

### View Backup History

```bash
ls -lh /mnt/raid10/proxmox-backup/transcripts/
```

### Restore from Backup

```bash
# Stop current container
docker-compose -f manifests/docker-compose.gen8.yml down

# Clear data directory
sudo rm -rf /mnt/raid10/transcript-pipeline/pgdata/*

# Start container
docker-compose -f manifests/docker-compose.gen8.yml up -d

# Wait for PostgreSQL to initialize
sleep 30

# Restore from backup
docker exec -i transcript-pipeline-postgres pg_restore \
    -U transcript_admin \
    -d transcripts \
    -F custom \
    -c \
    < /mnt/raid10/proxmox-backup/transcripts/transcript_db_YYYYMMDD_HHMMSS.dump
```

## Troubleshooting

### Container won't start

Check logs:
```bash
docker logs transcript-pipeline-postgres
```

Verify permissions:
```bash
ls -la /mnt/raid10/transcript-pipeline/pgdata
# Should be owned by 999:999
```

### Slow query performance

Analyze query plan:
```sql
EXPLAIN ANALYZE SELECT ... ;
```

Check index usage:
```sql
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;
```

### Connection refused

Verify container is running:
```bash
docker ps | grep transcript-pipeline-postgres
```

Check healthcheck:
```bash
docker inspect transcript-pipeline-postgres | jq '.[0].State.Health'
```

### RAID degraded

Check RAID status:
```bash
sudo mdadm --detail /dev/md0
```

If degraded, backup script will exit with code 2 and prevent backup until RAID is repaired.

## Performance Benchmarks

Expected performance on 128GB RAM system with RAID10 SSDs:

- **Vector similarity search**: <5ms for k=10 nearest neighbors
- **Full-text search**: <50ms for typical queries
- **Insert throughput**: 10,000+ rows/sec with batching
- **Concurrent connections**: 100 (configurable)

## Security Considerations

1. **Never commit .env file** - contains database credentials
2. **Use strong passwords** - 32+ character random strings
3. **Restrict network access** - bind to localhost or use firewall rules
4. **Regular backups** - automated daily with 30-day retention
5. **Monitor RAID health** - backup script verifies before each backup

## Future Enhancements

- pgvector GPU acceleration with CUDA support
- Connection pooling with PgBouncer
- Read replicas for horizontal scaling
- Monitoring with Prometheus + Grafana
- Automated schema migrations with Flyway/Liquibase

## File Structure

```
transcript-pipeline/
├── manifests/
│   └── docker-compose.gen8.yml      # Docker Compose configuration
├── scripts/
│   ├── setup/
│   │   ├── 02-configure-storage.sh   # Storage setup
│   │   └── 03-init-database.sh       # Database initialization
│   └── maintenance/
│       └── backup-database.sh         # Automated backup
├── sql/
│   └── schema/
│       ├── 001-init.sql               # Core schema
│       ├── 002-indexes.sql            # Performance indexes
│       └── 003-seed-tags.sql          # Initial taxonomy
├── .env.example                       # Environment template
└── DEPLOYMENT.md                      # This file
```

## Support

For issues or questions:
1. Check Docker logs: `docker logs transcript-pipeline-postgres`
2. Verify RAID health: `sudo mdadm --detail /dev/md0`
3. Review PostgreSQL logs: `/mnt/raid10/transcript-pipeline/pgdata/pg_log/`
