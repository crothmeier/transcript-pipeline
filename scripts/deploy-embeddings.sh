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
NAMESPACE="transcript-pipeline"
IMAGE_NAME="transcript-embeddings"
DEPLOYMENT_MANIFEST="${REPO_ROOT}/manifests/k3s/09-embeddings-deployment.yaml"
SERVICE_MANIFEST="${REPO_ROOT}/manifests/k3s/10-embeddings-service.yaml"

echo -e "${GREEN}Deploying BGE-M3 Embedding Service to K3s${NC}"
echo "Namespace: ${NAMESPACE}"
echo ""

# Check if image exists in K3s
echo -e "${YELLOW}Checking if image exists in K3s...${NC}"
if ! sudo k3s ctr images ls | grep -q "${IMAGE_NAME}"; then
    echo -e "${RED}Error: Image '${IMAGE_NAME}' not found in K3s${NC}"
    echo -e "${YELLOW}Please build and import the image first:${NC}"
    echo "  ./scripts/build-embeddings.sh"
    exit 1
fi

echo -e "${GREEN}Image found in K3s${NC}"
echo ""

# Check if manifests exist
if [[ ! -f "${DEPLOYMENT_MANIFEST}" ]]; then
    echo -e "${RED}Error: Deployment manifest not found at ${DEPLOYMENT_MANIFEST}${NC}"
    exit 1
fi

if [[ ! -f "${SERVICE_MANIFEST}" ]]; then
    echo -e "${RED}Error: Service manifest not found at ${SERVICE_MANIFEST}${NC}"
    exit 1
fi

# Apply the manifests
echo -e "${YELLOW}Applying deployment manifest...${NC}"
kubectl apply -f "${DEPLOYMENT_MANIFEST}"

echo -e "${YELLOW}Applying service manifest...${NC}"
kubectl apply -f "${SERVICE_MANIFEST}"

echo ""
echo -e "${GREEN}Manifests applied successfully${NC}"
echo ""

# Wait for the deployment to be ready
echo -e "${YELLOW}Waiting for pod to be ready (timeout: 300s)...${NC}"
echo "This may take several minutes as the model needs to be downloaded and loaded into GPU memory."
echo ""

if kubectl wait --for=condition=ready pod \
    -l app=embeddings \
    -n "${NAMESPACE}" \
    --timeout=300s; then
    echo ""
    echo -e "${GREEN}Pod is ready!${NC}"
else
    echo ""
    echo -e "${RED}Error: Pod failed to become ready within timeout${NC}"
    echo ""
    echo -e "${YELLOW}Pod status:${NC}"
    kubectl get pods -n "${NAMESPACE}" -l app=embeddings
    echo ""
    echo -e "${YELLOW}Recent pod events:${NC}"
    kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -n 20
    echo ""
    echo -e "${YELLOW}Pod logs (if available):${NC}"
    kubectl logs -n "${NAMESPACE}" -l app=embeddings --tail=50 || true
    exit 1
fi

# Get pod name
POD_NAME=$(kubectl get pods -n "${NAMESPACE}" -l app=embeddings -o jsonpath='{.items[0].metadata.name}')

# Test the health endpoint
echo ""
echo -e "${YELLOW}Testing health endpoint...${NC}"
HEALTH_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- curl -s http://localhost:8001/health)

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Health check successful:${NC}"
    echo "${HEALTH_OUTPUT}" | python3 -m json.tool 2>/dev/null || echo "${HEALTH_OUTPUT}"
else
    echo -e "${RED}Health check failed${NC}"
    exit 1
fi

# Display connection information
echo ""
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Service Information:${NC}"
echo "  Internal endpoint: http://embeddings.${NAMESPACE}.svc.cluster.local:8001"
echo "  Pod: ${POD_NAME}"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  View logs: kubectl logs -n ${NAMESPACE} ${POD_NAME} -f"
echo "  Port forward: kubectl port-forward -n ${NAMESPACE} ${POD_NAME} 8001:8001"
echo "  Get status: kubectl get pods -n ${NAMESPACE} -l app=embeddings"
echo "  Test embedding:"
echo "    kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -X POST http://localhost:8001/embed/batch \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"texts\": [\"Hello, world!\"]}'"
echo ""
echo -e "${YELLOW}Metrics endpoint:${NC}"
echo "  http://embeddings.${NAMESPACE}.svc.cluster.local:8001/metrics"
echo ""
