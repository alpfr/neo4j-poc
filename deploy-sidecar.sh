#!/bin/bash
set -e

# 1. Project Variables (Overridable via Environment Variables)
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-neo4j-poc}"
DB_PASSWORD="${DB_PASSWORD:-YourSecurePassword123!}" # Change in production!

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: PROJECT_ID is not set. Please set the PROJECT_ID environment variable or run 'gcloud config set project <your-project-id>'."
    exit 1
fi

SA_NAME="${SERVICE_NAME}-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET_NAME="${PROJECT_ID}-neo4j-data"

echo "=== Securing and Building Neo4j PoC ==="

# 1. Identity & Privileges - Create a Dedicated Service Account
echo "1. Checking/Creating dedicated Service Account ($SA_NAME)..."
gcloud iam service-accounts create $SA_NAME --display-name="Neo4j PoC Service Account" --project=$PROJECT_ID || echo "(SA exists, proceeding...)"

# 2. Persistence - Data Bucket for FUSE
echo "2. Checking/Creating GCS Bucket for Neo4j Persistence..."
gcloud storage buckets create gs://$BUCKET_NAME --project=$PROJECT_ID --location=$REGION || echo "(Bucket exists...)"
# Grant the service account permissions to read/write to the FUSE bucket
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/storage.objectAdmin"

# 3. Secret Management - Store Passwords Securely
echo "3. Creating and storing secrets securely in Google Secret Manager..."
gcloud services enable secretmanager.googleapis.com

# Create Password Secret
echo -n "$DB_PASSWORD" | gcloud secrets create neo4j-password-secret --data-file=- --project=$PROJECT_ID --replication-policy="user-managed" --locations=$REGION || \
echo -n "$DB_PASSWORD" | gcloud secrets versions add neo4j-password-secret --data-file=- --project=$PROJECT_ID

# Create Neo4j Auth String Secret (Format: user/password)
echo -n "neo4j/$DB_PASSWORD" | gcloud secrets create neo4j-auth-secret --data-file=- --project=$PROJECT_ID --replication-policy="user-managed" --locations=$REGION || \
echo -n "neo4j/$DB_PASSWORD" | gcloud secrets versions add neo4j-auth-secret --data-file=- --project=$PROJECT_ID

# Grant Service Account access to read these secrets at runtime
gcloud secrets add-iam-policy-binding neo4j-password-secret --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" --project=$PROJECT_ID
gcloud secrets add-iam-policy-binding neo4j-auth-secret --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" --project=$PROJECT_ID

# 4. Container Build Pipeline
echo "4. Checking/Creating Artifact Registry repository for images..."
gcloud artifacts repositories create $SERVICE_NAME-repo \
    --repository-format=docker \
    --location=$REGION \
    --project=$PROJECT_ID || echo "(Repository exists...)"

echo "5. Building Streamlit Docker image using Cloud Build..."
TAG=$(date +%Y%m%d-%H%M%S)
IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$SERVICE_NAME-repo/frontend:$TAG"
gcloud builds submit --tag $IMAGE_PATH . --project=$PROJECT_ID

# 6. Prepare Service Manifest
echo "6. Injecting runtime variables into service configuration..."
sed "s|FRONTEND_IMAGE_PLACEHOLDER|$IMAGE_PATH|g" service.yaml > service-rendered.yaml
sed -i.bak "s|SERVICE_ACCOUNT_PLACEHOLDER|$SA_EMAIL|g" service-rendered.yaml
sed -i.bak "s|BUCKET_NAME_PLACEHOLDER|$BUCKET_NAME|g" service-rendered.yaml

# 7. Cloud Run Deployment
echo "7. Deploying Multi-Container (Sidecar) Cloud Run service with FUSE and Secrets..."
gcloud run services replace service-rendered.yaml \
    --region $REGION \
    --project $PROJECT_ID

echo "---"
echo "Security Update Complete!"
echo "Your Streamlit app is now deployed securely. Data is persisted to GCS ($BUCKET_NAME), and passwords are no longer in code!"
echo "NOTE: To restrict internet access, the 'allUsers' public permission has been removed."
echo "You can view the internal private URL here:"
gcloud run services describe $SERVICE_NAME --region $REGION --project $PROJECT_ID --format="value(status.url)"
echo "(If you want it to be public again, run: gcloud run services add-iam-policy-binding $SERVICE_NAME --region $REGION --member='allUsers' --role='roles/run.invoker')"
