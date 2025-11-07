#!/usr/bin/env bash
# Initialize PostgreSQL database for transcript pipeline
# Installs extensions, runs schema files, and verifies deployment

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables from .env
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${RED}ERROR: .env file not found${NC}"
    echo "Create .env with: POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD"
    exit 1
fi

# Configuration
CONTAINER_NAME="transcript-pipeline-postgres"
POSTGRES_DB="${POSTGRES_DB:-transcripts}"
POSTGRES_USER="${POSTGRES_USER:-transcript_admin}"
MAX_RETRIES=30
RETRY_INTERVAL=2

echo -e "${GREEN}=== PostgreSQL Database Initialization ===${NC}"

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
for i in $(seq 1 ${MAX_RETRIES}); do
    if docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL is ready (attempt ${i}/${MAX_RETRIES})${NC}"
        break
    fi

    if [ $i -eq ${MAX_RETRIES} ]; then
        echo -e "${RED}ERROR: PostgreSQL failed to become ready after ${MAX_RETRIES} attempts${NC}"
        docker logs --tail 50 "${CONTAINER_NAME}"
        exit 1
    fi

    echo -e "${YELLOW}Waiting for PostgreSQL... (${i}/${MAX_RETRIES})${NC}"
    sleep ${RETRY_INTERVAL}
done

# Verify extensions are installed
echo -e "\n${YELLOW}Verifying PostgreSQL extensions...${NC}"
EXTENSIONS=("uuid-ossp" "pgvector" "pg_trgm")
for ext in "${EXTENSIONS[@]}"; do
    if docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        -c "SELECT 1 FROM pg_extension WHERE extname = '${ext}'" | grep -q 1; then
        echo -e "${GREEN}✓ Extension installed: ${ext}${NC}"
    else
        echo -e "${RED}ERROR: Extension not installed: ${ext}${NC}"
        exit 1
    fi
done

# Verify tables exist
echo -e "\n${YELLOW}Verifying database schema...${NC}"
TABLES=("transcripts" "tags" "transcript_tags")
for table in "${TABLES[@]}"; do
    if docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        -c "SELECT to_regclass('public.${table}')" | grep -q "${table}"; then
        echo -e "${GREEN}✓ Table exists: ${table}${NC}"
    else
        echo -e "${RED}ERROR: Table not found: ${table}${NC}"
        exit 1
    fi
done

# Verify indexes
echo -e "\n${YELLOW}Verifying indexes...${NC}"
INDEX_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public'")
echo -e "${GREEN}✓ Total indexes created: ${INDEX_COUNT}${NC}"

# Verify seed data
echo -e "\n${YELLOW}Verifying seed data...${NC}"
TAG_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -t -c "SELECT COUNT(*) FROM tags")
TAG_COUNT=$(echo ${TAG_COUNT} | xargs) # trim whitespace
if [ "${TAG_COUNT}" -gt 0 ]; then
    echo -e "${GREEN}✓ Seed tags loaded: ${TAG_COUNT} tags${NC}"
else
    echo -e "${RED}ERROR: No seed data found${NC}"
    exit 1
fi

# Display database statistics
echo -e "\n${YELLOW}Database statistics:${NC}"
docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" << 'EOF'
SELECT
    'Database' AS type,
    pg_database.datname AS name,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
WHERE datname = current_database()

UNION ALL

SELECT
    'Table' AS type,
    tablename AS name,
    pg_size_pretty(pg_total_relation_size(quote_ident(tablename)::regclass)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY type, name;
EOF

# Display connection information
echo -e "\n${GREEN}=== Database initialization complete ===${NC}"
echo -e "${YELLOW}Connection details:${NC}"
echo -e "  Host: localhost"
echo -e "  Port: 5432"
echo -e "  Database: ${POSTGRES_DB}"
echo -e "  User: ${POSTGRES_USER}"
echo -e "\n${YELLOW}Connection string:${NC}"
echo -e "  postgresql://${POSTGRES_USER}:<password>@localhost:5432/${POSTGRES_DB}"
echo -e "\n${YELLOW}Test connection:${NC}"
echo -e "  docker exec -it ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Configure backup cron job: scripts/maintenance/backup-database.sh"
echo -e "  2. Start ingesting transcripts into /mnt/raid10/transcript-pipeline/raw"
echo -e "  3. Monitor logs: docker logs -f ${CONTAINER_NAME}"
