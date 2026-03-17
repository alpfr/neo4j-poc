# PostgreSQL & Cloud Run Deployment Samples

When deploying applications that require a relational database like PostgreSQL on Google Cloud, the best practice is to use **Google Cloud SQL** rather than trying to run the database inside a container yourself. Google Cloud SQL provides managed backups, automatic failover, and native integration with Cloud Run via the Cloud SQL Auth Proxy.

Below are two sample scripts you can use as a blueprint: a manual Bash script and an automated Google Cloud Build pipeline.

---

## 1. Manual Bash Script (`deploy-postgres.sh`)

This script creates a Cloud SQL Postgres instance (if it doesn't exist), builds your Docker container, and deploys it to Cloud Run with the secure Cloud SQL connection attached.

```bash
#!/bin/bash
set -e

# Configuration Variables
PROJECT_ID="your-project-id"
REGION="us-central1"
DB_INSTANCE_NAME="my-postgres-db"
DB_NAME="myappdb"
DB_PASSWORD="SuperSecurePassword123!"
SERVICE_NAME="my-app-service"

echo "1. Enabling necessary APIs..."
gcloud services enable sqladmin.googleapis.com run.googleapis.com cloudbuild.googleapis.com --project=$PROJECT_ID

echo "2. Checking for Cloud SQL Postgres Instance..."
if ! gcloud sql instances describe $DB_INSTANCE_NAME --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "Creating Cloud SQL PostgreSQL instance (this takes approx 5-10 minutes)..."
    gcloud sql instances create $DB_INSTANCE_NAME \
        --database-version=POSTGRES_15 \
        --tier=db-f1-micro \
        --region=$REGION \
        --project=$PROJECT_ID \
        --root-password=$DB_PASSWORD
        
    echo "Creating database inside the instance..."
    gcloud sql databases create $DB_NAME \
        --instance=$DB_INSTANCE_NAME \
        --project=$PROJECT_ID
else
    echo "Database instance already exists!"
fi

echo "3. Building & Deploying to Cloud Run..."
# Note: Cloud Run natively mounts the socket at /cloudsql/PROJECT:REGION:INSTANCE
gcloud run deploy $SERVICE_NAME \
    --source . \
    --region $REGION \
    --project $PROJECT_ID \
    --add-cloudsql-instances $PROJECT_ID:$REGION:$DB_INSTANCE_NAME \
    --set-env-vars DB_USER=postgres,DB_PASS=$DB_PASSWORD,DB_NAME=$DB_NAME,DB_HOST=/cloudsql/$PROJECT_ID:$REGION:$DB_INSTANCE_NAME \
    --allow-unauthenticated

echo "Deployment Complete!"
```

---

## 2. Automated CI/CD Pipeline (`cloudbuild-postgres.yaml`)

This is the equivalent automated pipeline. If you connect this to a GitHub trigger, every code push will ensure the database infrastructure exists, build your app, and deploy it to Cloud Run.

```yaml
steps:
  # 1. Provision Cloud SQL PostgreSQL (Only creates if missing)
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        if ! gcloud sql instances describe ${_DB_INSTANCE_NAME} --project=${PROJECT_ID} > /dev/null 2>&1; then
          echo "Creating Cloud SQL PostgreSQL instance..."
          gcloud sql instances create ${_DB_INSTANCE_NAME} \
            --database-version=POSTGRES_15 \
            --tier=db-f1-micro \
            --region=${_REGION} \
            --project=${PROJECT_ID} \
            --root-password=${_DB_ROOT_PASSWORD}
            
          gcloud sql databases create ${_DB_NAME} \
            --instance=${_DB_INSTANCE_NAME} \
            --project=${PROJECT_ID}
        else
          echo "Cloud SQL instance already exists."
        fi

  # 2. Build the Application Container
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/app:${COMMIT_SHA}', '.']

  # 3. Push Container to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/app:${COMMIT_SHA}']

  # 4. Deploy to Cloud Run with attached Postgres DB
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        gcloud run deploy ${_SERVICE_NAME} \
          --image ${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/app:${COMMIT_SHA} \
          --region ${_REGION} \
          --project ${PROJECT_ID} \
          --add-cloudsql-instances ${PROJECT_ID}:${_REGION}:${_DB_INSTANCE_NAME} \
          --set-env-vars DB_USER=postgres,DB_PASS=${_DB_ROOT_PASSWORD},DB_NAME=${_DB_NAME},DB_HOST=/cloudsql/${PROJECT_ID}:${_REGION}:${_DB_INSTANCE_NAME} \
          --allow-unauthenticated

substitutions:
  _REGION: 'us-central1'
  _REPO_NAME: 'postgres-poc-repo'
  _SERVICE_NAME: 'postgres-app'
  _DB_INSTANCE_NAME: 'production-postgres-db'
  _DB_NAME: 'app_database'
  _DB_ROOT_PASSWORD: 'ChangeMeInCloudBuildTriggers!' # In a real scenario, use Secret Manager!

images:
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/app:${COMMIT_SHA}'

options:
  defaultLogsBucketBehavior: REGIONAL_USER_OWNED_BUCKET
```

### Key Difference from Neo4j Sidecars
Notice the `--add-cloudsql-instances` flag. Google Cloud Run has built-in native support for Cloud SQL! Unlike Neo4j where we had to inject a full database instance inside a "Sidecar" container in the same pod, Google automatically securely mounts the Postgres database socket directly at `/cloudsql/` so your application code can connect to it seamlessly via Unix Domain Sockets without exposing the database to the public internet!

---

## 3. Automated Deletion Pipeline (Teardown)

If you are running ephemeral environments or need to safely tear down the provisioned Cloud SQL database and Cloud Run service via an automated pipeline, you can use the `cloudbuild-postgres-destroy.yaml` file.

This pipeline gracefully deletes both the Cloud Run deployment and the Cloud SQL databases instances.

```yaml
steps:
  # 1. Delete Cloud Run Service
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Deleting Cloud Run service ${_SERVICE_NAME}..."
        gcloud run services delete ${_SERVICE_NAME} \
          --region=${_REGION} \
          --project=${PROJECT_ID} \
          --quiet || echo "Service not found or already deleted."

  # 2. Delete Cloud SQL PostgreSQL Instance
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Deleting Cloud SQL PostgreSQL instance ${_DB_INSTANCE_NAME}..."
        # The --quiet flag is essential to bypass the interactive confirmation prompt
        gcloud sql instances delete ${_DB_INSTANCE_NAME} \
          --project=${PROJECT_ID} \
          --quiet || echo "Database instance not found or already deleted."

substitutions:
  _REGION: 'us-central1'
  _SERVICE_NAME: 'postgres-app'
  _DB_INSTANCE_NAME: 'production-postgres-db'

options:
  defaultLogsBucketBehavior: REGIONAL_USER_OWNED_BUCKET
```
