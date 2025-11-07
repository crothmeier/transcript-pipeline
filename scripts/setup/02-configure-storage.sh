#!/usr/bin/env bash
# Configure RAID10 storage for transcript pipeline PostgreSQL deployment
# Requires: mdadm RAID10 mounted at /mnt/raid10

set -euo pipefail

# Color output for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RAID_MOUNT="/mnt/raid10"
BASE_DIR="${RAID_MOUNT}/transcript-pipeline"
PGDATA_DIR="${BASE_DIR}/pgdata"
RAW_DIR="${BASE_DIR}/raw"
BACKUP_DIR="/mnt/raid10/proxmox-backup/transcripts"
POSTGRES_UID=999
POSTGRES_GID=999

echo -e "${GREEN}=== Transcript Pipeline Storage Configuration ===${NC}"

# Verify RAID10 is mounted
if ! mountpoint -q "${RAID_MOUNT}"; then
    echo -e "${RED}ERROR: ${RAID_MOUNT} is not mounted${NC}"
    exit 1
fi

echo -e "${GREEN}✓ RAID mount verified: ${RAID_MOUNT}${NC}"

# Check mdadm RAID health
echo -e "\n${YELLOW}Checking RAID array health...${NC}"
RAID_DEVICE=$(df "${RAID_MOUNT}" | tail -1 | awk '{print $1}')
if [[ "${RAID_DEVICE}" =~ /dev/md ]]; then
    RAID_STATUS=$(sudo mdadm --detail "${RAID_DEVICE}" | grep "State :" | awk '{print $3}')
    if [[ "${RAID_STATUS}" != "clean" ]]; then
        echo -e "${RED}WARNING: RAID array is ${RAID_STATUS}${NC}"
        echo -e "${YELLOW}Run 'sudo mdadm --detail ${RAID_DEVICE}' for details${NC}"
    else
        echo -e "${GREEN}✓ RAID array is clean${NC}"
    fi
else
    echo -e "${YELLOW}Note: ${RAID_DEVICE} is not an mdadm array${NC}"
fi

# Create directory structure
echo -e "\n${YELLOW}Creating directory structure...${NC}"
sudo mkdir -p "${PGDATA_DIR}" "${RAW_DIR}" "${BACKUP_DIR}"

# Set ownership to postgres user (UID 999 in pgvector/pgvector:pg16 image)
echo -e "${YELLOW}Setting permissions for PostgreSQL (UID ${POSTGRES_UID})...${NC}"
sudo chown -R ${POSTGRES_UID}:${POSTGRES_GID} "${PGDATA_DIR}"
sudo chmod 700 "${PGDATA_DIR}"

# Raw transcripts directory: readable by postgres and current user
sudo chown -R ${POSTGRES_UID}:${POSTGRES_GID} "${RAW_DIR}"
sudo chmod 755 "${RAW_DIR}"

# Backup directory: writable by postgres
sudo chown -R ${POSTGRES_UID}:${POSTGRES_GID} "${BACKUP_DIR}"
sudo chmod 755 "${BACKUP_DIR}"

# Display disk usage
echo -e "\n${YELLOW}Disk usage:${NC}"
df -h "${RAID_MOUNT}" | tail -1

echo -e "\n${YELLOW}Directory structure:${NC}"
ls -lah "${BASE_DIR}"

# Verify ext4 filesystem
FS_TYPE=$(df -T "${RAID_MOUNT}" | tail -1 | awk '{print $2}')
if [[ "${FS_TYPE}" != "ext4" ]]; then
    echo -e "${YELLOW}WARNING: Filesystem is ${FS_TYPE}, expected ext4${NC}"
else
    echo -e "${GREEN}✓ Filesystem: ext4${NC}"
fi

echo -e "\n${GREEN}=== Storage configuration complete ===${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Create .env file with database credentials"
echo -e "  2. Run: docker-compose -f manifests/docker-compose.gen8.yml up -d"
echo -e "  3. Run: scripts/setup/03-init-database.sh"
