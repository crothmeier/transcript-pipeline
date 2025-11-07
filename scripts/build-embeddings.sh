#!/bin/bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="transcript-embeddings"
IMAGE_TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
TARBALL_PATH="/tmp/embeddings.tar"

echo -e "${GREEN}Building BGE-M3 Embedding Service${NC}"
echo "Repository: ${REPO_ROOT}"
echo "Image: ${FULL_IMAGE}"
echo ""

# Navigate to repo root
cd "${REPO_ROOT}"

# Check if Dockerfile exists
if [[ ! -f "src/embeddings/Dockerfile" ]]; then
    echo -e "${RED}Error: Dockerfile not found at src/embeddings/Dockerfile${NC}"
    exit 1
fi

# Build the Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build \
    -t "${FULL_IMAGE}" \
    -f src/embeddings/Dockerfile \
    src/embeddings/

if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Docker build failed${NC}"
    exit 1
fi

echo -e "${GREEN}Docker image built successfully${NC}"
echo ""

# Save the image to a tarball
echo -e "${YELLOW}Saving image to tarball...${NC}"
docker save "${FULL_IMAGE}" -o "${TARBALL_PATH}"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to save image to tarball${NC}"
    exit 1
fi

echo -e "${GREEN}Image saved to ${TARBALL_PATH}${NC}"
echo ""

# Import the image into K3s
echo -e "${YELLOW}Importing image into K3s...${NC}"
sudo k3s ctr images import "${TARBALL_PATH}"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to import image into K3s${NC}"
    echo -e "${YELLOW}Cleaning up tarball...${NC}"
    rm -f "${TARBALL_PATH}"
    exit 1
fi

echo -e "${GREEN}Image imported into K3s successfully${NC}"
echo ""

# Cleanup tarball
echo -e "${YELLOW}Cleaning up tarball...${NC}"
rm -f "${TARBALL_PATH}"

# Verify the import
echo -e "${YELLOW}Verifying import...${NC}"
if sudo k3s ctr images ls | grep -q "${IMAGE_NAME}"; then
    echo -e "${GREEN}Image verified in K3s:${NC}"
    sudo k3s ctr images ls | grep "${IMAGE_NAME}"
    echo ""
    echo -e "${GREEN}Build and import completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Deploy the service: ./scripts/deploy-embeddings.sh"
    echo "2. Check deployment status: kubectl get pods -n transcript-pipeline -l app=embeddings"
    echo "3. View logs: kubectl logs -n transcript-pipeline -l app=embeddings -f"
else
    echo -e "${RED}Error: Image not found in K3s after import${NC}"
    exit 1
fi
