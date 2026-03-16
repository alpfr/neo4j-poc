#!/bin/bash
set -e

PROJECT_ID="alpfr-splunk-integration"
REGION="us-central1"
SERVICE_NAME="neo4j-poc"

echo "1. Checking/Creating Artifact Registry repository for images..."
gcloud artifacts repositories create $SERVICE_NAME-repo \
    --repository-format=docker \
    --location=$REGION \
    --project=$PROJECT_ID || echo "(Repository likely exists, proceeding...)"

# Generate a unique tag based on the current timestamp
TAG=$(date +%Y%m%d-%H%M%S)
IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$SERVICE_NAME-repo/frontend:$TAG"

echo "2. Building Streamlit Docker image using Cloud Build..."
gcloud builds submit --tag $IMAGE_PATH . --project=$PROJECT_ID

echo "3. Replacing generic image placeholder in service.yaml with current image..."
sed "s|FRONTEND_IMAGE_PLACEHOLDER|$IMAGE_PATH|g" service.yaml > service-rendered.yaml

echo "4. Deploying Multi-Container (Sidecar) Cloud Run service..."
gcloud run services replace service-rendered.yaml \
    --region $REGION \
    --project $PROJECT_ID

echo "5. Allowing unauthenticated external access to Streamlit..."
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --region $REGION \
    --project $PROJECT_ID \
    --member="allUsers" \
    --role="roles/run.invoker"

echo "---"
echo "All done! Your Streamlit app is now public, and the Neo4j database is securely running in its sidecar!"
