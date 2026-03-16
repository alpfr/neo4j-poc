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
```

---

## 2. Essential Privileges (IAM Roles)

To deploy the application and manage the infrastructure using the provided scripts, the user (or service account) executing `gcloud` commands must have the following IAM roles:

- **Cloud Run Admin** (`roles/run.admin`): To deploy and manage Cloud Run services.
- **Service Account User** (`roles/iam.serviceAccountUser`): Required to deploy on Cloud Run (usually attached to the Compute Engine default service account).
- **Artifact Registry Administrator** (`roles/artifactregistry.admin`): To create image repositories and push images.
- **Cloud Build Editor** (`roles/cloudbuild.builds.editor`): To trigger and manage Cloud Build jobs.
- **Project IAM Admin** (`roles/resourcemanager.projectIamAdmin`): (Optional, but required if you want the script to automatically invoke `add-iam-policy-binding` to make the service public).

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
    spec:
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
          value: "mypassword123"

      # 2. Neo4j Database Sidecar
      - image: neo4j:5.18.0
        name: neo4j-db
        env:
        - name: NEO4J_AUTH
          value: "neo4j/mypassword123"
```

### B. The Deployment Script (`deploy-sidecar.sh`)

This script orchestrates the entire release pipeline on GCP from your local machine.

```bash
#!/bin/bash
set -e

PROJECT_ID="alpfr-splunk-integration"
REGION="us-central1"
SERVICE_NAME="neo4j-poc"

# 1. Create Artifact Registry Repository (if not exists)
# Artifact Registry is the modern replacement for Container Registry, providing secure, regional image storage.
gcloud artifacts repositories create $SERVICE_NAME-repo ...

# 2. Assign a Dynamic Image Tag & Build Streamlit Image in Cloud Build
# Best Practice: We use a timestamp-based tag instead of 'latest' so we can confidently rollback to previous image versions.
TAG=$(date +%Y%m%d-%H%M%S)
IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$SERVICE_NAME-repo/frontend:$TAG"
gcloud builds submit --tag $IMAGE_PATH . ...

# 3. Inject Image URL into YAML
sed "s|FRONTEND_IMAGE_PLACEHOLDER|$IMAGE_PATH|g" service.yaml > service-rendered.yaml

# 4. Deploy Sidecar architecture
gcloud run services replace service-rendered.yaml ...

# 5. Make publicly accessible
gcloud run services add-iam-policy-binding $SERVICE_NAME ...
```

---

## 6. Execution Instructions

1. Ensure `deploy-sidecar.sh` is executable:
   ```bash
   chmod +x deploy-sidecar.sh
   ```
2. Run the deployment script:
   ```bash
   ./deploy-sidecar.sh
   ```
3. Once finished, retrieve the live URL:
   ```bash
   gcloud run services describe neo4j-poc --region us-central1 --format="value(status.url)"
   ```
4. Open the Web App URL, paste a Cypher query in the UI, and interact with your Cloud Run powered Neo4j Database!
