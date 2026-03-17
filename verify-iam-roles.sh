#!/bin/bash
set -e

# Default to the active gcloud config settings if arguments are not provided
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
ACCOUNT_EMAIL="${1:-$(gcloud config get-value account 2>/dev/null)}"

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: Could not determine PROJECT_ID. Please set it via 'gcloud config set project <PROJECT_ID>'"
    exit 1
fi

if [ -z "$ACCOUNT_EMAIL" ]; then
    echo "ERROR: Could not determine active Google Cloud account. Please authenticate via 'gcloud auth login'"
    exit 1
fi

echo "========================================================="
echo " Verifying IAM Roles for: $ACCOUNT_EMAIL"
echo " Project: $PROJECT_ID"
echo "========================================================="
echo "Fetching active IAM policy from Google Cloud..."

# Fetch the raw IAM policy for the specific project, filtered to only return the roles for the target account
AVAILABLE_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --format="value(bindings.role)" \
    --filter="bindings.members:$ACCOUNT_EMAIL AND (bindings.condition:None OR bindings.condition.title:None OR -bindings.condition.title:*)" 2>/dev/null || echo "")

# Define the roles we expect to see for broad Cloud Build / Cloud Run capabilities
REQUIRED_ROLES=(
    "roles/run.admin"
    "roles/iam.serviceAccountUser"
    "roles/artifactregistry.writer"
    "roles/cloudbuild.builds.builder"
    "roles/cloudsql.admin"
    "roles/container.developer"
    "roles/secretmanager.secretAccessor"
    "roles/logging.logWriter"
    "roles/storage.admin"
)

# First check if the user is an owner/editor which supersedes the granular roles
if echo "$AVAILABLE_ROLES" | grep -q "roles/owner"; then
    echo "✅ [GRANTED] - roles/owner (Inherits all required permissions)"
    echo "========================================================="
    echo "✅ Verification Complete! You have full administrative access."
    exit 0
fi

if echo "$AVAILABLE_ROLES" | grep -q "roles/editor"; then
    echo "✅ [GRANTED] - roles/editor (Inherits execution permissions)"
    echo "⚠️  Note: Editors can execute builds and deployments, but cannot safely assign/modify other IAM roles."
fi

MISSING_ROLES=0

for role in "${REQUIRED_ROLES[@]}"; do
    # Simple regex to check if the exact role string exists in the fetched list
    if echo "$AVAILABLE_ROLES" | grep -q "${role}"; then
        echo "✅ [GRANTED] - $role"
    else
        echo "❌ [MISSING] - $role"
        MISSING_ROLES=$((MISSING_ROLES + 1))
    fi
done

echo "========================================================="
if [ "$MISSING_ROLES" -eq 0 ]; then
    echo "✅ Verification Complete! The account has all explicitly required granular roles."
else
    echo "❌ Verification Failed! The account is missing $MISSING_ROLES required granular roles."
    echo ""
    echo "Resolution:"
    echo "If checking a specific Service Account, you can run: ./assign-iam-roles.sh"
    echo "If checking your human user account, ask your GCP Project Administrator to grant you the missing roles."
fi
