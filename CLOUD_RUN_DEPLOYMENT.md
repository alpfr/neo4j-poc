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
3. Run the automated Sidecar deployment script:

```bash
chmod +x deploy-sidecar.sh
./deploy-sidecar.sh
```

### What the Script Does:
1. **Creates Identity & Storage:** Generates a dedicated Service Account and a Google Cloud Storage bucket to persist Neo4j data via Cloud Run FUSE volumes.
2. **Manages Secrets:** Creates Google Secret Manager vaults to store the Neo4j admin passwords, meaning no credentials exist in plaintext inside the YAML.
3. **Builds the Image:** Uses Google Cloud Build to construct the Streamlit Docker image securely (as a non-root user) and pushes it to Artifact Registry.
4. **Prepares the Manifest:** Finds the dynamically generated image URL and updates `service.yaml` while wiring up the FUSE volumes and Secrets securely via substitutions.
5. **Deploys to Cloud Run:** Uses `gcloud run services replace` to publish the multi-container configuration containing Neo4j's TCP Liveness Probes.
6. **Restricts Access:** Previously public, the service is now protected by Google IAM implicitly (meaning you need IAP or `roles/run.invoker` to hit the web app).
## Limitations & CLI Usage

Because the sidecar architecture intentionally hides the Bolt port from external traffic, **you cannot run your local `cli.py` against the Cloud Run database directly** from your personal machine.

To use the Python CLI:
- Use it locally while running a local Neo4j Docker container (`bolt://localhost:7687`).
- Connect it to a managed Neo4j Aura cluster (`neo4j+s://...`).
- Execute commands securely in the browser through the deployed Streamlit app instead.
