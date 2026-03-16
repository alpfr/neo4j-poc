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

### 2. Networking & Zero-Trust Security
*   **Internal DNS:** Streamlit points to `bolt://neo4j-service:7687` instead of `localhost`. The Kubernetes master handles internal routing seamlessly.
*   **Strict NetworkPolicies:** The `network-policy.yaml` explicitly drops all unaccounted traffic, locking down ingress and egress. Neo4j is cordoned off entirely—only the labeled Streamlit pod is whitelisted to reach port 7687.
*   **Ingress & Istio VirtualService:** The cluster exposes Streamlit to the internet securely over standard HTTPS/80 using NGINX `Ingress` routing and an Istio `VirtualService` for traffic mesh capabilities.

### 3. Elastic Autoscaling
*   **HPA (Horizontal Pod Autoscaler):** If Streamlit CPU utilization spikes algorithmically over 70%, the cluster dynamically provisions duplicate Streamlit pods (up to 10 instances) to handle user traffic.
*   **VPA (Vertical Pod Autoscaler):** Because databases scale vertically, the VPA dynamically assesses Neo4j query intensity and will inject larger CPU/RAM allocations onto the database pod during heavy graph computations.

### 4. Configuration & Observability
*   **ConfigMaps & Secrets:** Base variables are centralized in `configmap.yaml`, while sensitive passwords are compartmentalized in a native Kubernetes `Secret`.
*   **ServiceMonitors:** Both Streamlit and Neo4j expose a `/metrics` endpoint specifically labeled for arbitrary Prometheus/Grafana scrape clusters.

## CI/CD Pipeline `cloudbuild-gke.yaml`

We have abandoned the manual `deploy-sidecar.sh` methodology in favor of an automated Google Cloud Build CI/CD Pipeline.

Whenever code is pushed to the `main` branch, Google Cloud Build executes `cloudbuild-gke.yaml`:
1. **Container Build:** The frontend Docker image is built natively on Google servers.
2. **Artifact Registry Push:** The immutably tagged SHA image is pushed.
3. **Kustomize Injection:** By running `kustomize edit set image`, the new Docker tag is safely injected into our declarative state.
4. **Declarative Apply:** The pipeline executes `kubectl apply -k kubernetes/`, computing the precise drift and hydrating the cluster without downtime.
