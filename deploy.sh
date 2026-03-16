#!/bin/bash
set -e

PROJECT_ID="alpfr-splunk-integration"
REGION="us-central1"
SERVICE_NAME="neo4j-poc"

echo "Deploying Neo4j Streamlit PoC to Cloud Run..."

gcloud run deploy $SERVICE_NAME \
  --source . \
  --project $PROJECT_ID \
  --region $REGION \
  --port 8501 \
  --allow-unauthenticated \
  --set-env-vars="NEO4J_URI=${NEO4J_URI:-bolt://localhost:7687},NEO4J_USER=${NEO4J_USER:-neo4j},NEO4J_PASSWORD=${NEO4J_PASSWORD:-password}"

echo "Deployment completed!"
