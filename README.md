# Neo4j Proof of Concept (PoC)

This repository contains a Proof of Concept for a Neo4j Graph Database application deployed on Google Cloud Run using the "Sidecar" pattern securely. It features a Python Streamlit frontend with interactive Physics-based graph visualization.

## Important Documentation
For detailed explanations of the architecture, deployment scripts, and security integrations, please read the following guides:
1. [GCP Deployment Guide](GCP_DEPLOYMENT_GUIDE.md) - Instructions to set up IAM, Secrets, FUSE (if used), and service deployments.
2. [Cloud Run Deployment Reference](CLOUD_RUN_DEPLOYMENT.md) - Deep dive into the Sidecar architecture and limitations.
3. [Sample Data & Queries](SAMPLE_DATA_AND_QUERIES.md) - How to populate the database and use the Interactive Graph Visualizer. 

## Features
- **Streamlit Web UI**: Execute Cypher queries natively from your browser.
- **Dual Tab View**: View query results natively as flat Pandas dataframes, or mathematically rendered as Interactive physics graphs.
- **Secure Sidecar**: Neo4j Database is hidden from the public internet entirely. It is accessed by Streamlit locally over `localhost:7687`.
- **Secret Manager**: Passwords injected at runtime via Google Cloud Secret Manager.

## Quickstart
1. Set up your `.env` file using `.env.template`.
2. Ensure you have the required GCP Permissions.
3. Execute `./deploy-sidecar.sh`.
