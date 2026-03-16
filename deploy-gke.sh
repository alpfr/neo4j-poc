#!/bin/bash
set -e

# Project Variables (Overridable via Environment Variables)
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-neo4j-gke-cluster}"
DB_PASSWORD="${DB_PASSWORD:-YourSecurePassword123!}"

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: PROJECT_ID is not set. Please set the PROJECT_ID environment variable or run 'gcloud config set project <your-project-id>'."
    exit 1
fi

echo "=== Securing and Building Neo4j PoC for GKE ==="

# 1. Enable Required GKE APIs
echo "1. Enabling Kubernetes Engine (GKE) API..."
gcloud services enable container.googleapis.com --project=$PROJECT_ID

# 2. Provide GKE Cluster
echo "2. Checking/Creating GKE Cluster ($CLUSTER_NAME)..."
# Uses Autopilot for zero-maintenance container provisioning
gcloud container clusters describe $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID >/dev/null 2>&1 || \
gcloud container clusters create-auto $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID

# Get cluster credentials so kubectl can communicate with the new cluster
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID

# 3. Kubernetes Secret
echo "3. Creating Kubernetes Secret for Neo4j Database..."
kubectl create secret generic neo4j-secrets --from-literal=neo4j-password="$DB_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -

# 4. Build & Push Image
echo "4. Checking/Creating Artifact Registry repository for images..."
gcloud artifacts repositories create neo4j-poc-repo \
    --repository-format=docker \
    --location=$REGION \
    --project=$PROJECT_ID || echo "(Repository exists...)"

echo "5. Building Streamlit Docker image using Cloud Build..."
TAG=$(date +%Y%m%d-%H%M%S)
IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/neo4j-poc-repo/frontend:$TAG"
gcloud builds submit --tag $IMAGE_PATH . --project=$PROJECT_ID

# 6. Inject Image to Manifest
echo "6. Applying Kubernetes manifests..."
sed "s|FRONTEND_IMAGE_PLACEHOLDER|$IMAGE_PATH|g" kubernetes/streamlit-deployment.yaml > kubernetes/streamlit-deployment-rendered.yaml

# 7. Apply Manifests
kubectl apply -f kubernetes/neo4j-statefulset.yaml
kubectl apply -f kubernetes/neo4j-service.yaml
kubectl apply -f kubernetes/streamlit-deployment-rendered.yaml
kubectl apply -f kubernetes/streamlit-service.yaml

echo "---"
echo "Deployment applied successfully to Google Kubernetes Engine (GKE)!"
echo "Neo4j is now running statefully with persistent SSD storage."
echo "Waiting for Google to provision the External Load Balancer IP for Streamlit..."
echo "Run the following command in 2 minutes to get your live IP Address:"
echo "kubectl get service streamlit-service"
