#!/usr/bin/env bash
# Automated PostgreSQL backup with RAID health verification
# Usage: Run daily via cron for production backups
# Return codes: 0=success, 1=dump failed, 2=raid degraded

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
CONTAINER_NAME="transcript-pipeline-postgres"
BACKUP_DIR="/mnt/raid10/proxmox-backup/transcripts"
RETENTION_DAYS=30
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/transcript_db_${TIMESTAMP}.dump"
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"
RAID_MOUNT="/mnt/raid10"

# Load environment variables
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${RED}ERROR: .env file not found${NC}" | tee -a "${LOG_FILE}"
    exit 1
fi

POSTGRES_DB="${POSTGRES_DB:-transcripts}"
POSTGRES_USER="${POSTGRES_USER:-transcript_admin}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log "${GREEN}=== PostgreSQL Backup Started ===${NC}"

# Verify RAID health before backup
log "${YELLOW}Checking RAID array health...${NC}"
RAID_DEVICE=$(df "${RAID_MOUNT}" | tail -1 | awk '{print $1}')

if [[ "${RAID_DEVICE}" =~ /dev/md ]]; then
    RAID_STATUS=$(sudo mdadm --detail "${RAID_DEVICE}" | grep "State :" | awk '{print $3}')

    if [[ "${RAID_STATUS}" != "clean" ]]; then
        log "${RED}CRITICAL: RAID array is ${RAID_STATUS}${NC}"
        log "${RED}Backup aborted due to RAID degradation${NC}"

        # Send RAID status to log
        sudo mdadm --detail "${RAID_DEVICE}" >> "${LOG_FILE}"

        # Exit with RAID error code
        exit 2
    else
        log "${GREEN}✓ RAID array is clean${NC}"
    fi
else
    log "${YELLOW}Note: ${RAID_DEVICE} is not an mdadm array, skipping RAID check${NC}"
fi

# Verify PostgreSQL container is running
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    log "${RED}ERROR: PostgreSQL container ${CONTAINER_NAME} is not running${NC}"
    exit 1
fi

# Verify PostgreSQL is accepting connections
if ! docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" > /dev/null 2>&1; then
    log "${RED}ERROR: PostgreSQL is not accepting connections${NC}"
    exit 1
fi

log "${GREEN}✓ PostgreSQL is ready${NC}"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Perform pg_dump with custom format and compression
log "${YELLOW}Starting database dump...${NC}"
START_TIME=$(date +%s)

if docker exec "${CONTAINER_NAME}" pg_dump \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -F custom \
    -Z 9 \
    -f "/var/lib/postgresql/data/backups/$(basename ${BACKUP_FILE})" \
    2>> "${LOG_FILE}"; then

    # Move backup from container to host
    docker cp "${CONTAINER_NAME}:/var/lib/postgresql/data/backups/$(basename ${BACKUP_FILE})" "${BACKUP_FILE}"

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | awk '{print $1}')

    log "${GREEN}✓ Backup completed successfully${NC}"
    log "Backup file: ${BACKUP_FILE}"
    log "Backup size: ${BACKUP_SIZE}"
    log "Duration: ${DURATION} seconds"

    # Verify backup integrity
    if docker exec "${CONTAINER_NAME}" pg_restore \
        --list \
        "/var/lib/postgresql/data/backups/$(basename ${BACKUP_FILE})" \
        > /dev/null 2>&1; then
        log "${GREEN}✓ Backup integrity verified${NC}"
    else
        log "${RED}WARNING: Backup integrity check failed${NC}"
    fi

    # Clean up temporary file in container
    docker exec "${CONTAINER_NAME}" rm -f "/var/lib/postgresql/data/backups/$(basename ${BACKUP_FILE})"
else
    log "${RED}ERROR: Database dump failed${NC}"
    exit 1
fi

# Cleanup old backups (retention policy)
log "${YELLOW}Applying retention policy (${RETENTION_DAYS} days)...${NC}"
DELETED_COUNT=0
while IFS= read -r old_backup; do
    rm -f "${old_backup}"
    DELETED_COUNT=$((DELETED_COUNT + 1))
    log "Deleted old backup: $(basename ${old_backup})"
done < <(find "${BACKUP_DIR}" -name "transcript_db_*.dump" -type f -mtime +${RETENTION_DAYS})

if [ ${DELETED_COUNT} -eq 0 ]; then
    log "${GREEN}No old backups to delete${NC}"
else
    log "${GREEN}✓ Deleted ${DELETED_COUNT} old backup(s)${NC}"
fi

# Also cleanup old log files
find "${BACKUP_DIR}" -name "backup_*.log" -type f -mtime +${RETENTION_DAYS} -delete

# Display backup summary
log "${YELLOW}Backup summary:${NC}"
CURRENT_BACKUPS=$(find "${BACKUP_DIR}" -name "transcript_db_*.dump" -type f | wc -l)
TOTAL_BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | awk '{print $1}')
log "Total backups: ${CURRENT_BACKUPS}"
log "Total backup size: ${TOTAL_BACKUP_SIZE}"

# Get database statistics
log "${YELLOW}Database statistics:${NC}"
docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t << 'EOF' | tee -a "${LOG_FILE}"
SELECT
    'Transcripts: ' || COUNT(*) || ' records'
FROM transcripts

UNION ALL

SELECT
    'Tags: ' || COUNT(*) || ' records'
FROM tags

UNION ALL

SELECT
    'Transcript-Tags: ' || COUNT(*) || ' records'
FROM transcript_tags

UNION ALL

SELECT
    'Database size: ' || pg_size_pretty(pg_database_size(current_database()));
EOF

log "${GREEN}=== Backup completed successfully ===${NC}"

# Display RAID status summary
RAID_HEALTH=$(sudo mdadm --detail "${RAID_DEVICE}" 2>/dev/null | grep "State :" | awk '{print $3}' || echo "N/A")
log "RAID status: ${RAID_HEALTH}"

exit 0
