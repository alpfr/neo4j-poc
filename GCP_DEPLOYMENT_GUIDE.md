# Neo4j & Streamlit App on GCP Cloud Run Deployment Guide

This comprehensive guide outlines how to build, deploy, and configure a PoC for a Neo4j-backed Streamlit web application on Google Cloud Run using the Sidecar container pattern.

---

## 1. Google Cloud Services to Enable

Before beginning the deployment, you must ensure your Google Cloud project (e.g., `alpfr-splunk-integration`) has the following APIs and services enabled. You can enable these via the Google Cloud Console or using the following `gcloud` commands:

```bash
# Enable Cloud Run API
gcloud services enable run.googleapis.com

# Enable Artifact Registry API (to store Docker images)
gcloud services enable artifactregistry.googleapis.com

# Enable Cloud Build API (to build Docker images in the cloud)
gcloud services enable cloudbuild.googleapis.com

# Enable IAM API
gcloud services enable iam.googleapis.com

# Enable Secret Manager API
gcloud services enable secretmanager.googleapis.com
```

---

## 2. Essential Privileges (IAM Roles)

To deploy the application and manage the infrastructure using the provided scripts, the user (or service account) executing `gcloud` commands must have the following IAM roles:

- **Cloud Run Admin** (`roles/run.admin`): To deploy and manage Cloud Run services.
- **Service Account User** (`roles/iam.serviceAccountUser`): Required to deploy on Cloud Run (usually attached to the Compute Engine default service account).
- **Artifact Registry Administrator** (`roles/artifactregistry.admin`): To create image repositories and push images.
- **Cloud Build Editor** (`roles/cloudbuild.builds.editor`): To trigger and manage Cloud Build jobs.
- **Project IAM Admin** (`roles/resourcemanager.projectIamAdmin`): Required to automatically provision new secure Service Accounts and assign FUSE/Secret manager bindings.
- **Secret Manager Admin** (`roles/secretmanager.admin`): To create new vaults and inject DB passwords.
- **Storage Admin** (`roles/storage.admin`): To create the GCS bucket for FUSE persistence.
---

## 3. Creating the Application

Here is a breakdown of the core files required to run the Web App.

### `app.py`
The Streamlit frontend that connects to Neo4j. It reads from environment variables, uses `@st.cache_resource` for connection pooling, and provides a text area to run and display Cypher queries.

### `cli.py`
A terminal utility using the `neo4j` Python driver that connects to the database utilizing identical environment variables `NEO4J_URI`, `NEO4J_USER`, and `NEO4J_PASSWORD`.

### `requirements.txt`
Specifies library versions:
```text
streamlit>=1.32.0
neo4j>=5.18.0
pandas>=2.2.0
```

### `Dockerfile`
A container image definition for the Streamlit app. It copies the code, installs dependencies, exposes port `8501`, and defines the Streamlit startup command.

---

## 4. Understanding TCP Limitations and the Sidecar Architecture

Google Cloud Run intercepts incoming requests and only routes **HTTP/HTTPS** traffic to your containers. Neo4j, however, operates on its custom binary protocol called **Bolt** (running over raw TCP, natively on port `7687`).

If you deployed Neo4j as a standalone Cloud Run service, Streamlit would not be able to talk to it over the public internet because Cloud Run drops all incoming TCP packets on port `7687`.

**The Solution: Cloud Run Sidecars (Multi-Container deployment)**
Sidecar containers allow you to run multiple Docker images inside the exact same underlying Cloud Run instance. They share a network namespace.
1. The Neo4j container acts as a local database.
2. The Streamlit container can connect directly via `bolt://localhost:7687`.
3. Only the Streamlit container exposes a public port (`8501`) to the internet.

---

## 5. The Deployment Assets

To execute this architecture, we use a custom YAML configuration and a deployment shell script.

### A. The Configuration (`service.yaml`)

This Knative configuration file defines the exact Cloud Run service footprint.

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: neo4j-poc
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/execution-environment: gen2
        run.googleapis.com/launch-stage: BETA # Required for GCS FUSE
    spec:
      serviceAccountName: SERVICE_ACCOUNT_PLACEHOLDER
      volumes:
        - name: neo4j-data
          csi:
            driver: gcsfuse.run.googleapis.com
            volumeAttributes:
              bucketName: BUCKET_NAME_PLACEHOLDER

      containers:
      # 1. Streamlit Application
      - image: FRONTEND_IMAGE_PLACEHOLDER # Overwritten dynamically by bash script
        name: frontend
        ports:
        - containerPort: 8501
        env:
        - name: NEO4J_URI
          value: "bolt://localhost:7687"
        - name: NEO4J_USER
          value: "neo4j"
        - name: NEO4J_PASSWORD
          valueFrom:
            secretKeyRef:
              name: neo4j-password-secret
              key: latest
        resources:
          limits:
            memory: 512Mi
            cpu: 1000m

      # 2. Neo4j Database Sidecar
      - image: neo4j:5.18.0
        name: neo4j-db
        env:
        - name: NEO4J_AUTH
          valueFrom:
            secretKeyRef:
               name: neo4j-auth-secret
               key: latest
        startupProbe:
          tcpSocket:
            port: 7687
          initialDelaySeconds: 15
          timeoutSeconds: 2
          failureThreshold: 20
          periodSeconds: 5
        livenessProbe:
          tcpSocket:
            port: 7687
          initialDelaySeconds: 10
          periodSeconds: 15
        resources:
          limits:
            memory: 1Gi
            cpu: 1000m
        volumeMounts:
          - name: neo4j-data
            mountPath: /data
```

### B. The Deployment Script (`deploy-sidecar.sh`)

This script orchestrates the entire secure release pipeline dynamically, allowing it to be used across any GCP Project. It pulls variables either from `.env` or from your system's active `gcloud config`.

```bash
#!/bin/bash
set -e

# Project Variables (Overridable via Environment Variables)
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-neo4j-poc}"
DB_PASSWORD="${DB_PASSWORD:-YourSecurePassword123!}"

echo "1. Checking/Creating dedicated Service Account ($SA_NAME)..."
# ... creates minimal privilege Service Accounts

echo "2. Checking/Creating GCS Bucket for Neo4j Persistence..."
# ... provisions FUSE volume for stateful data

echo "3. Creating and storing secrets securely in Google Secret Manager..."
# ... saves database passwords without writing plaintext YAML

echo "4. Checking/Creating Artifact Registry repository for images..."
# ... uses secure repository

echo "5. Building Streamlit Docker image using Cloud Build..."
TAG=$(date +%Y%m%d-%H%M%S)
# ... builds and timestamps the image dynamically

echo "6. Injecting runtime variables into service configuration..."
# ... replaces IMAGE, BUCKET, and SA placeholders in yaml

echo "7. Deploying Multi-Container (Sidecar) Cloud Run service with FUSE and Secrets..."
gcloud run services replace service-rendered.yaml ...
```

---

## 6. Execution Instructions

The deployment script supports `.env` structures out of the box so multiple Developers can securely point it at different GCP projects.

1. Configure your environment by copying the template file:
   ```bash
   cp .env.template .env
   ```
2. Open `.env` and fill in your target `PROJECT_ID` and your chosen secure `DB_PASSWORD`.
3. Ensure `deploy-sidecar.sh` is executable:
   ```bash
   chmod +x deploy-sidecar.sh
   ```
4. Run the deployment script:
   ```bash
   source .env && ./deploy-sidecar.sh
   # Or simply execute it directly, as it will fallback to your active `gcloud config`
   ```
5. Note: The application is deployed securely over IAM. You must access it as an authenticated Google Cloud User.
   ```bash
   gcloud run services describe neo4j-poc --region us-central1 --format="value(status.url)"
   ```
6. Open the Web App URL, paste a Cypher query in the UI, and interact with your Cloud Run powered Neo4j Database!
