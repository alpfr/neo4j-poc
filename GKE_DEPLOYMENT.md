# Neo4j and Streamlit on Google Kubernetes Engine (GKE)

This document explains the production-grade architecture and deployment pipeline for migrating the Neo4j PoC from the serverless Cloud Run environment into a robust container orchestration engine using **Google Kubernetes Engine (GKE)**.

## Why GKE?
While Cloud Run's Sidecar pattern is an excellent, low-cost method for spinning up temporary PoC environments, it lacks the ability to reliably attach true **block storage** (like SSDs). Network drives (like GCS FUSE) cause fatal boot-loop errors due to Neo4j's requirement for POSIX-compliant memory-mapped IO. Consequently, the Cloud Run implementation of the PoC relies on ephemeral memory that is wiped any time the container scales to zero.

By migrating to GKE, we decouple the Streamlit application from the database and grant Neo4j persistent, highly-available local disk storage. 

## The Enterprise Kubernetes Architecture

The `kubernetes/` directory contains a complete suite of standard K8s manifests managed via **Kustomize**, providing a highly secure, auto-scaling, and observable system:

### 1. Stateful Storage & Decoupling
*   **Decoupled Workloads:** Streamlit (`streamlit-deployment.yaml`) and Neo4j (`neo4j-statefulset.yaml`) now run on completely isolated pods, preventing a web traffic spike from crashing the core database.
*   **StatefulSets & PVCs:** Neo4j is configured as a `StatefulSet` with an associated `PersistentVolumeClaim` (PVC) requesting 20GB of standard `ReadWriteOnce` block storage. If the Neo4j pod crashes, Kubernetes guarantees its replacement will automatically reattach exactly to the previous SSD, ensuring zero data loss.

### 2. Networking & Load Balancing
*   **Internal DNS:** Streamlit securely points to `bolt://neo4j-service:7687` instead of `localhost`. The Kubernetes master handles internal proxy routing seamlessly.
*   **External LoadBalancer:** The cluster natively exposes Streamlit to the internet over a dynamically provisioned Google Cloud Layer-4 TCP `LoadBalancer` connected to `streamlit-service`, completely bypassing the need for complex Nginx Ingress controllers or Anthos Service Meshes.

### 3. Elastic Autoscaling
*   **HPA (Horizontal Pod Autoscaler):** If Streamlit CPU utilization spikes algorithmically over 70%, the cluster dynamically provisions duplicate Streamlit pods (up to 10 instances) to handle user traffic.
*   **VPA (Vertical Pod Autoscaler):** Because databases scale vertically, the VPA dynamically assesses Neo4j query intensity and will inject larger CPU/RAM allocations onto the database pod during heavy graph computations.

### 4. GKE Autopilot & Component Hotfixes
*   **Storage Access (fsGroup):** By default, GKE PDs attach as `root`. We apply `securityContext.fsGroup: 7474` to forcibly grant the `neo4j` pod native write access to the SSD, preventing fatal boot crashes.
*   **Environment Variable Collision:** Kubernetes intelligently injects service variables (like `NEO4J_SERVICE_PORT`). Neo4j's exact config parser misidentifies these, triggering strict validation crashes. This architecture explicitly sets `enableServiceLinks: false` on the pod and renames standard secrets to `DB_PASSWORD` to fully decouple Kubernetes variables from the database engine.
*   **Streamlit Component Rendering:** Advanced `agraph` Javascript bundles fail to load cross-origin behind unencrypted external TCP LoadBalancers. The project ships with a `.streamlit/config.toml` explicitly enabling `enableStaticServing: true` and disabling WebSocket compression to perfectly patch this proxy disconnect.

## CI/CD Pipeline `cloudbuild-gke.yaml`

We have abandoned the manual `deploy-sidecar.sh` methodology in favor of an automated Google Cloud Build CI/CD Pipeline.

Whenever code is pushed to the `main` branch, Google Cloud Build executes `cloudbuild-gke.yaml`:
1. **Container Build:** The frontend Docker image is built natively on Google servers.
2. **Artifact Registry Push:** The immutably tagged SHA image is pushed.
3. **Kustomize Injection:** By running `kustomize edit set image`, the new Docker tag is safely injected into our declarative state.
4. **Declarative Apply:** The pipeline executes `kubectl apply -k kubernetes/`, computing the precise drift and hydrating the cluster without downtime.

---

## Manual Deployment (Step-by-Step)

If you prefer to bypass automated webhooks and trigger the GKE architecture piece-by-piece from your local terminal via Cloud Build, run these raw commands:

### Step 1: Provision the Autopilot Cluster & Get Credentials
Before Cloud Build can push Kubernetes manifests, the cluster must physically exist.
```bash
export PROJECT_ID="alpfr-splunk-integration"

# Enable the GKE API
gcloud services enable container.googleapis.com --project=$PROJECT_ID

# Create the cluster (Takes 5-10 minutes)
gcloud container clusters create-auto neo4j-gke-cluster \
  --region=us-central1 \
  --project=$PROJECT_ID

# Download the Kubeconfig credentials so your CLI can talk to the new cluster
gcloud container clusters get-credentials neo4j-gke-cluster \
  --region=us-central1 \
  --project=$PROJECT_ID
```

### Step 2: Establish the Kubernetes Secrets
Our GKE pipeline mounts the Neo4j password directly as a native Kubernetes Secret.
```bash
export DB_PASSWORD="YourSecurePassword123!"

# Define the password as a native K8s secret inside the cluster
kubectl create secret generic neo4j-secrets \
  --from-literal=neo4j-password="$DB_PASSWORD"
```

### Step 3: Scaffold the Artifact Registry
Cloud Build needs a secure digital warehouse to store your compiled Docker images.
```bash
gcloud artifacts repositories create neo4j-poc-repo \
  --repository-format=docker \
  --location=us-central1 \
  --description="Private Docker repository for Neo4j Streamlit app"
```

### Step 4: Execute the Cloud Build GKE Pipeline
This command constructs the Docker image, safely rewrites your Kubernetes YAML locally using Kustomize, and applies it against your GKE cluster remotely!
```bash
gcloud builds submit --config cloudbuild-gke.yaml \
  --project=$PROJECT_ID \
  --substitutions=_REGION="us-central1",_REPO_NAME="neo4j-poc-repo",_CLUSTER_NAME="neo4j-gke-cluster"
```

### Step 5: Get Your Live Application URL
Kubernetes instances spin up an External Load Balancer connected to a static IP address. To grab your live IP address after the build finishes, run:
```bash
kubectl get service streamlit-service
```
Wait roughly 2 minutes and look purely for the **`EXTERNAL-IP`** column. Copy and paste that IP into your browser to launch your Neo4j Graph!
