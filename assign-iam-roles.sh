#!/bin/bash
set -e

# Configuration 
PROJECT_ID="alpfr-splunk-integration"
SERVICE_ACCOUNT_NAME="neo4j-poc-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "========================================================="
echo " Configuring Service Account: ${SERVICE_ACCOUNT_EMAIL} "
echo "========================================================="

# 1. Ensure the Service Account exists
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Creating new Service Account: ${SERVICE_ACCOUNT_NAME}..."
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="CI/CD Deployment Service Account" \
        --project="${PROJECT_ID}"
else
    echo "Service Account already exists. Proceeding to assign roles..."
fi

# 2. Define the Required Roles Array
# These are the absolute minimum roles required for Cloud Build to provision
# Cloud Run, Cloud SQL, Artifact Registry, and Google Kubernetes Engine resources.
ROLES=(
    "roles/run.admin"                   # Create/Update Cloud Run Services
    "roles/iam.serviceAccountUser"      # Allow Cloud Build to act as the SA
    "roles/artifactregistry.writer"     # Push generated Docker images to Artifact Registry
    "roles/cloudbuild.builds.builder"   # Native permission to execute Cloud Build steps
    "roles/cloudsql.admin"              # Create/Update PostgreSQL/Cloud SQL databases dynamically
    "roles/container.developer"         # Perform 'kubectl apply' to update GKE Clusters
    "roles/secretmanager.secretAccessor" # Read database passwords from Secret Manager
    "roles/logging.logWriter"           # Write Cloud Build logs to the GCP console natively
    "roles/storage.admin"               # Read/Write to Google Cloud Storage (Bucket logs & FUSE)
)

echo " "
echo "Assigning ${#ROLES[@]} IAM Roles to ${SERVICE_ACCOUNT_EMAIL}..."

# 3. Apply the Roles Iteratively
for role in "${ROLES[@]}"; do
    echo "  -> Applying ${role}..."
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="${role}" \
        --condition=None \
        >/dev/null 2>&1
done

echo " "
echo "✓ Success! All necessary IAM Roles have been securely bound to your Service Account."
echo "You can now safely execute Cloud Build and Cloud Run deployments."
