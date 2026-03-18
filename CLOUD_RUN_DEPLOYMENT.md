# Neo4j and Streamlit on Google Cloud Run (Sidecar Architecture)

This document explains the architecture and deployment process for the Neo4j-backed Streamlit application running on Google Cloud Run.

## Architecture: The "Sidecar" Pattern

Google Cloud Run is designed to serve HTTP/HTTPS traffic. However, Neo4j uses its own custom binary protocol called **Bolt** (running over standard TCP, typically on port 7687) for database connections. 

If we deployed the deeply-coupled Neo4j database as its own distinct Cloud Run service, Streamlit would not be able to connect to it because Cloud Run drops raw TCP packets from external internet traffic. 

To overcome this, we use a **Sidecar Deployment architecture**.

### What is a Sidecar?
In a Sidecar deployment, multiple containers share the exact same Cloud Run instance (the same underlying virtual machine and network namespace). 
1. **Container A (Frontend):** The Streamlit Python application exposing port `8501`.
2. **Container B (Sidecar):** The Neo4j database server.

**Benefits:**
- Streamlit can connect to the Neo4j database securely and purely locally using `bolt://localhost:7687`.
- The database's port (`7687`) is **never exposed** to the public internet. Only the web app is externally accessible on port `8501`.
- Both containers scale together up and down based on traffic.

*Note: For this PoC, Neo4j is running in ephemeral mode inside the sidecar. If the Cloud Run instance scales to zero, database state is cleared. A persistent production setup should use Neo4j Aura, Compute Engine, or a stateful GKE deployment.*

## Deployment Steps

Deploying the sidecar requires building the application image, writing an advanced `service.yaml`, and replacing the service in Cloud Run. We have automated this entirely.

1. Review the application code in `app.py` and the database connection settings.
2. Ensure you have authorized the `gcloud` CLI with sufficient permissions.
3. Configure your environment by creating a `.env` file (you can copy `.env.template`). 
4. Run the automated deployment script:

```bash
source .env && ./deploy-sidecar.sh
```

### What the Script Does:
1. **Creates Identity & Storage:** Generates a dedicated Service Account and a Google Cloud Storage bucket to persist Neo4j data via Cloud Run FUSE volumes.
2. **Manages Secrets:** Creates Google Cloud Secret Manager vaults to store the Neo4j admin passwords, meaning no credentials exist in plaintext inside the YAML.
3. **Builds the Image:** Uses Google Cloud Build to construct the Streamlit Docker image securely (as a non-root user) and pushes it to Artifact Registry.
4. **Prepares the Manifest:** Finds the dynamically generated image URL and updates `service.yaml` while wiring up the FUSE volumes and Secrets securely via substitutions.
5. **Deploys to Cloud Run:** Uses `gcloud run services replace` to publish the multi-container configuration containing Neo4j's TCP Liveness Probes.
6. **Restricts Access:** Previously public, the service is now protected by Google IAM implicitly (meaning you need IAP or `roles/run.invoker` to hit the web app).

---

## Manual Deployment (Step-by-Step)

If you prefer to bypass the wrapper script and execute the architecture piece-by-piece via Cloud Build, run these raw terminal commands:

### Step 1: Secure Your Permissions & Storage
Ensure your `gcloud` account is authorized:
```bash
gcloud auth login
```
*(If you are deploying this manually via a Service Account pipeline, ensure it has been granted permissions using `./assign-iam-roles.sh`)*.

### Step 2: Establish the Secret Manager Vaults
Instead of committing plain-text database passwords, create securely encrypted vaults.
```bash
export DB_PASSWORD="YourSecurePassword123!"

gcloud secrets create neo4j-password-secret --replication-policy="automatic"
gcloud secrets create neo4j-auth-secret --replication-policy="automatic"

echo -n "${DB_PASSWORD}" | gcloud secrets versions add neo4j-password-secret --data-file=-
echo -n "neo4j/${DB_PASSWORD}" | gcloud secrets versions add neo4j-auth-secret --data-file=-
```

### Step 3: Scaffold an Artifact Registry
Cloud Build needs a secure digital warehouse to store the compiled Docker image.
```bash
gcloud artifacts repositories create neo4j-poc-repo \
  --repository-format=docker \
  --location=us-central1 \
  --description="Private Docker repository for Neo4j Streamlit app"
```

### Step 4: Execute the Cloud Build Pipeline
This securely compiles your Streamlit Application, pushes it to your new Artifact Registry, and natively injects your unique variables straight into `service.yaml`.
```bash
gcloud builds submit --config cloudbuild.yaml \
  --project="alpfr-splunk-integration" \
  --substitutions=_REGION="us-central1",_REPO_NAME="neo4j-poc-repo",_SERVICE_NAME="neo4j-poc",_SERVICE_ACCOUNT_EMAIL="neo4j-poc-sa@alpfr-splunk-integration.iam.gserviceaccount.com"
```

## Limitations & CLI Usage

Because the sidecar architecture intentionally hides the Bolt port from external traffic, **you cannot run your local `cli.py` against the Cloud Run database directly** from your personal machine.

To use the Python CLI:
- Use it locally while running a local Neo4j Docker container (`bolt://localhost:7687`).
- Connect it to a managed Neo4j Aura cluster (`neo4j+s://...`).
- Execute commands securely in the browser through the deployed Streamlit app instead.

### Accessing Neo4j from Other Applications

Because of the Sidecar Architecture, **other applications cannot connect directly to this Neo4j database.** Cloud Run strictly blocks arbitrary TCP ports (like Neo4j's Bolt port `7687`) from the outside world.

If you need multiple external applications (like other microservices, mobile apps, or local CLI scripts) to connect to the same Neo4j database, you must unbundle the Sidecar. Your three options are:

1. **Build an API Gateway (The "Cloud Run" Way)**
   Replace Streamlit with a Python API (using FastAPI/Flask). Your API safely receives standard HTTP requests, connects to the local Neo4j sidecar, and returns the graph data as standard JSON.
   
2. **Use Neo4j AuraDB (The "Managed Cloud" Way - Recommended)**
   Stop self-hosting the database entirely. Use Neo4j AuraDB (which has a free tier) to get a secure `neo4j+s://` URI endpoint. Your Streamlit app, CLI scripts, and any other external application can connect directly without worrying about TCP networking or sidecars.
   
3. **Deploy to a Dedicated VM or Kubernetes (The "DevOps" Way)**
   Deploy Neo4j onto a standard Google Compute Engine VM or an internal GKE StatefulSet, where you have full control over opening port 7687 on the VPC Firewall.
