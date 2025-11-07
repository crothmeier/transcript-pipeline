#!/bin/bash
# Deploy transcript-pipeline to K3s cluster
# Prerequisites: kubectl configured, K3s cluster running, Gen8 node available

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== K3s Transcript Pipeline Deployment ===${NC}"

# Check kubectl access
echo -e "\n${YELLOW}[1/9] Checking kubectl access...${NC}"
if ! kubectl version --short &> /dev/null; then
    echo -e "${RED}Error: kubectl not configured or K3s cluster not accessible${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl access confirmed${NC}"

# Get Gen8 hostname
echo -e "\n${YELLOW}[2/9] Detecting Gen8 node hostname...${NC}"
echo "Available nodes:"
kubectl get nodes -o wide
echo ""
read -p "Enter the Gen8 node hostname (e.g., gen8.local): " GEN8_HOSTNAME

if [ -z "$GEN8_HOSTNAME" ]; then
    echo -e "${RED}Error: Gen8 hostname cannot be empty${NC}"
    exit 1
fi

# Update manifests with Gen8 hostname
echo -e "\n${YELLOW}[3/9] Updating manifests with Gen8 hostname...${NC}"
sed -i "s/GEN8_HOSTNAME/${GEN8_HOSTNAME}/g" manifests/k3s/04-postgres-pv.yaml
sed -i "s/GEN8_HOSTNAME/${GEN8_HOSTNAME}/g" manifests/k3s/06-postgres-statefulset.yaml
echo -e "${GREEN}✓ Manifests updated${NC}"

# Create namespace if not exists
echo -e "\n${YELLOW}[4/9] Creating namespace...${NC}"
if kubectl get namespace transcript-pipeline &> /dev/null; then
    echo -e "${GREEN}✓ Namespace already exists${NC}"
else
    kubectl create namespace transcript-pipeline
    echo -e "${GREEN}✓ Namespace created${NC}"
fi

# Update PostgreSQL password in secret
echo -e "\n${YELLOW}[5/9] Configuring PostgreSQL password...${NC}"
read -s -p "Enter PostgreSQL password (or press Enter to use default): " POSTGRES_PASSWORD
echo ""

if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD="CHANGE_ME_BEFORE_DEPLOY"
    echo -e "${YELLOW}⚠ Using default password - CHANGE THIS IN PRODUCTION${NC}"
else
    # Update secret manifest
    sed -i "s/CHANGE_ME_BEFORE_DEPLOY/${POSTGRES_PASSWORD}/g" manifests/k3s/01-postgres-secret.yaml
    echo -e "${GREEN}✓ Password updated in secret${NC}"
fi

# Apply all manifests using kustomize
echo -e "\n${YELLOW}[6/9] Applying Kubernetes manifests...${NC}"
kubectl apply -k manifests/k3s/
echo -e "${GREEN}✓ Manifests applied${NC}"

# Wait for StatefulSet to be ready
echo -e "\n${YELLOW}[7/9] Waiting for PostgreSQL StatefulSet to be ready...${NC}"
echo "This may take a few minutes..."
if kubectl wait --for=condition=ready pod -l app=postgres -n transcript-pipeline --timeout=300s; then
    echo -e "${GREEN}✓ PostgreSQL StatefulSet is ready${NC}"
else
    echo -e "${RED}Error: PostgreSQL StatefulSet failed to become ready${NC}"
    echo "Check pod status with: kubectl get pods -n transcript-pipeline"
    echo "Check logs with: kubectl logs -n transcript-pipeline postgres-0"
    exit 1
fi

# Run database initialization job
echo -e "\n${YELLOW}[8/9] Running database initialization job...${NC}"
# Delete existing job if it exists
kubectl delete job postgres-init -n transcript-pipeline --ignore-not-found=true
# Apply the job
kubectl apply -f manifests/k3s/08-init-db-job.yaml
echo "Waiting for job to complete..."
if kubectl wait --for=condition=complete job/postgres-init -n transcript-pipeline --timeout=180s; then
    echo -e "${GREEN}✓ Database initialization complete${NC}"
    # Show job logs
    echo -e "\nJob logs:"
    kubectl logs -n transcript-pipeline job/postgres-init
else
    echo -e "${RED}Error: Database initialization job failed${NC}"
    echo "Check job status with: kubectl get jobs -n transcript-pipeline"
    echo "Check logs with: kubectl logs -n transcript-pipeline job/postgres-init"
    exit 1
fi

# Verify deployment
echo -e "\n${YELLOW}[9/9] Verifying deployment...${NC}"
echo "PostgreSQL extensions:"
kubectl exec -n transcript-pipeline postgres-0 -- psql -U transcript_user -d transcripts_db -c '\dx' || true

echo -e "\n${GREEN}=== Deployment Summary ===${NC}"
echo "Namespace: transcript-pipeline"
echo "Services:"
kubectl get svc -n transcript-pipeline

echo -e "\n${GREEN}=== Access Information ===${NC}"
echo "To access PostgreSQL from your local machine:"
echo -e "${YELLOW}kubectl port-forward -n transcript-pipeline svc/postgres 5432:5432${NC}"
echo ""
echo "Connection details:"
echo "  Host: localhost (via port-forward) or postgres.transcript-pipeline.svc.cluster.local (from cluster)"
echo "  Port: 5432"
echo "  Database: transcripts_db"
echo "  User: transcript_user"
echo "  Password: (the one you configured)"

echo -e "\n${GREEN}=== Useful Commands ===${NC}"
echo "View pods:        kubectl get pods -n transcript-pipeline"
echo "View logs:        kubectl logs -n transcript-pipeline postgres-0"
echo "Exec into pod:    kubectl exec -it -n transcript-pipeline postgres-0 -- bash"
echo "Delete all:       kubectl delete namespace transcript-pipeline"

echo -e "\n${GREEN}✓ Deployment complete!${NC}"
