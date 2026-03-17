# Neo4j Proof of Concept (PoC)

This repository contains a Proof of Concept for a Neo4j Graph Database application deployed on Google Cloud Run using the "Sidecar" pattern securely. It features a Python Streamlit frontend with interactive Physics-based graph visualization.

## Important Documentation
For detailed explanations of the dual deployments (Serverless vs Container Orchestration) and our automated CI/CD pipelines, please read the following guides:
1. [GCP Deployment Guide](GCP_DEPLOYMENT_GUIDE.md) - Instructions to set up IAM, Secrets, FUSE (if used), and service deployments.
2. [Cloud Run Deployment Reference](CLOUD_RUN_DEPLOYMENT.md) - Deep dive into the Sidecar architecture and limitations.
3. [GKE Production Architecture](GKE_DEPLOYMENT.md) - Deep dive into migrating the PoC to Enterprise Kubernetes (StatefulSets, PVC, HPA, Ingress, Istio).
4. [Sample Data & Queries](SAMPLE_DATA_AND_QUERIES.md) - How to populate the database and use the Interactive Graph Visualizer. 
5. [Roadmap and Production Recommendations](RECOMMENDATIONS.md) - Important steps for moving from a PoC to a production-ready system.
6. [PostgreSQL on Cloud Run Sample](POSTGRES_CLOUDRUN_SAMPLE.md) - Sample CI/CD pipeline and Bash scripts for deploying to Cloud Run with native Cloud SQL integration.
7. [Automated CI/CD Triggers Guide](CI_CD_TRIGGERS_GUIDE.md) - Instructions on linking GitHub and GitLab to Google Cloud Build.

## Features
- **Streamlit Web UI**: Execute Cypher queries natively from your browser.
- **Dual Tab View**: View query results natively as flat Pandas dataframes, or mathematically rendered as Interactive physics graphs.
- **Secure Sidecar**: Neo4j Database is hidden from the public internet entirely. It is accessed by Streamlit locally over `localhost:7687`.
- **Secret Manager**: Passwords injected at runtime via Google Cloud Secret Manager.

## Quickstart (Manual Deployment)
1. Set up your `.env` file using `.env.template`.
2. Ensure you have the required GCP Permissions.
3. Execute `./deploy-sidecar.sh` (for Cloud Run) or `./deploy-gke.sh` (for Kubernetes).

## Automated Deployment (CI/CD)
This project includes automated Google Cloud Build pipelines. 
By connecting this repository to a Cloud Build Trigger targeting `main`, both `cloudbuild.yaml` (Cloud Run) and `cloudbuild-gke.yaml` (Kubernetes) can automatically build and deploy new code updates on every push.
