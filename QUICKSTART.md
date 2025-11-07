# Quick Start Guide - PostgreSQL Deployment

5-minute deployment guide for AI transcript pipeline.

## Prerequisites

- RAID10 mounted at `/mnt/raid10`
- Docker and Docker Compose installed
- 128GB RAM available

## Deployment Commands

```bash
# 1. Configure storage
./scripts/setup/02-configure-storage.sh

# 2. Create credentials
cp .env.example .env
# Edit .env and set POSTGRES_PASSWORD

# 3. Start PostgreSQL
docker-compose -f manifests/docker-compose.gen8.yml up -d

# 4. Initialize database
./scripts/setup/03-init-database.sh

# 5. Setup daily backups (optional)
crontab -e
# Add: 0 2 * * * /home/crathmene/git/transcript-pipeline/scripts/maintenance/backup-database.sh
```

## Verify Deployment

```bash
# Check container status
docker ps | grep transcript-pipeline-postgres

# Test connection
docker exec -it transcript-pipeline-postgres psql -U transcript_admin -d transcripts -c "\dt"

# Run manual backup test
./scripts/maintenance/backup-database.sh
```

## Connection Info

**Connection string:**
```
postgresql://transcript_admin:<password>@localhost:5432/transcripts
```

**Interactive shell:**
```bash
docker exec -it transcript-pipeline-postgres psql -U transcript_admin -d transcripts
```

## Common Operations

**Insert transcript:**
```sql
INSERT INTO transcripts (source, raw_content, filepath)
VALUES ('test.mp4', 'Sample transcript text', '/mnt/raid10/transcript-pipeline/raw/test.mp4');
```

**View tags:**
```sql
SELECT name, category, obsidian_folder FROM tags ORDER BY category, name;
```

**Tag a transcript:**
```sql
INSERT INTO transcript_tags (transcript_id, tag_id, confidence, assigned_by)
VALUES (
    (SELECT id FROM transcripts WHERE filepath = '/mnt/raid10/transcript-pipeline/raw/test.mp4'),
    (SELECT id FROM tags WHERE name = 'kubernetes/troubleshooting'),
    0.85,
    'manual'
);
```

**Vector similarity search (after adding embeddings):**
```sql
SELECT source, summary
FROM transcripts
ORDER BY embedding <=> '[0.1, 0.2, ..., 0.5]'::vector(1024)
LIMIT 5;
```

## Monitoring

**Database size:**
```bash
docker exec transcript-pipeline-postgres psql -U transcript_admin -d transcripts -c "SELECT pg_size_pretty(pg_database_size('transcripts'));"
```

**Record counts:**
```bash
docker exec transcript-pipeline-postgres psql -U transcript_admin -d transcripts -c "SELECT 'transcripts' AS table, COUNT(*) FROM transcripts UNION ALL SELECT 'tags', COUNT(*) FROM tags UNION ALL SELECT 'transcript_tags', COUNT(*) FROM transcript_tags;"
```

**RAID health:**
```bash
sudo mdadm --detail /dev/md0 | grep "State :"
```

## Troubleshooting

**Container won't start:**
```bash
docker logs transcript-pipeline-postgres
sudo chown -R 999:999 /mnt/raid10/transcript-pipeline/pgdata
```

**Connection refused:**
```bash
docker exec transcript-pipeline-postgres pg_isready -U transcript_admin -d transcripts
```

**Slow queries:**
```sql
-- Enable query timing
\timing on
-- Check indexes
SELECT schemaname, tablename, indexname FROM pg_indexes WHERE schemaname = 'public';
```

See `DEPLOYMENT.md` for comprehensive documentation.
