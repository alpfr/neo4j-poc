# Connecting Cloud Build Triggers (GitHub & GitLab)

This guide walks you through automatically triggering the Cloud Build CI/CD pipelines defined in this repository (`cloudbuild.yaml`, `cloudbuild-gke.yaml`, or `cloudbuild-postgres.yaml`) whenever a team member merges code into the `main` branch.

Google Cloud Build natively supports integrating with GitHub and GitLab.

---

## 🔒 Prerequisites: Service Account Permissions

Before setting up a trigger, you must ensure the Cloud Build Service Account has the required permissions to execute the actions within your YAML file.

By default, the Cloud Build service account looks like:
`[PROJECT_NUMBER]@cloudbuild.gserviceaccount.com`

**Go to IAM & Admin > IAM and verify the following roles.**

*   **For Cloud Run Deployments (Default):**
    *   `Cloud Run Admin`
    *   `Service Account User`
*   **For PostgreSQL Deployments (`cloudbuild-postgres.yaml`):**
    *   `Cloud SQL Admin` (Required to dynamically spin up new databases)
*   **For GKE Kubernetes Deployments (`cloudbuild-gke.yaml`):**
    *   `Kubernetes Engine Developer`
*   **Global Logging Requirement (For Custom Service Accounts):**
    *   `Logs Writer` (`roles/logging.logWriter`) - Essential for the build system to actually stream execution logs to the GCP console.

---

## 🛠 Option 1: GitHub Integration (Recommended)

Google Cloud has a native, streamlined GitHub integration.

1.  **Open Google Cloud Console** and navigate to **Cloud Build** → **Triggers**.
2.  Click **Create Trigger** at the top.
3.  **Name:** `github-main-deploy` (or similar).
4.  **Event:** Select **Push to a branch**.
5.  **Repository:** 
    *   Under "Source", click the dropdown and select **Connect New Repository**.
    *   Select **GitHub** and authorize the Cloud Build app to access your GitHub profile.
    *   Select the specific repository from your list.
6.  **Branch Name (Regex):** `^main$` (This ensures the build only fires on the main/master branch, not feature branches).
7.  **Configuration:** 
    *   Under "Type", choose **Cloud Build configuration file (yaml or json)**.
    *   Under "Location", type the exact filename you want to fire: (e.g., `cloudbuild-postgres.yaml`).
8.  **Service Account:** Verify it is using your authorized IAM service account.
9.  Click **Create**.

*Result: The next time you type `git push origin main` in your terminal, Cloud Build will instantly spin up a server, read the YAML, and execute the deployment.*

---

## 🦊 Option 2: GitLab Integration

Google Cloud now fully supports GitLab integrations natively, though it requires a Personal Access Token (PAT).

1.  **Generate a GitLab Token:**
    *   In GitLab, go to your User Profile → **Preferences** → **Access Tokens**.
    *   Create a token with `api` and `read_repository` scopes. Copy this token.
2.  **Connect Repository to GCP:**
    *   Open Google Cloud Console and go to **Cloud Build** → **Repositories**.
    *   Click **Connect Repository** and select the **GitLab** tab.
    *   Paste your GitLab token so GCP can automatically install the webhook into your repository.
3.  **Create the Trigger:**
    *   Navigate to **Cloud Build** → **Triggers** and click **Create Trigger**.
    *   **Name:** `gitlab-main-deploy`
    *   **Event:** Push to a branch (`^main$`).
    *   **Source:** Select your newly linked GitLab repository from the dropdown.
    *   **Configuration:** Enter your target file name (e.g., `cloudbuild-postgres.yaml`).
4.  Click **Create**.

*Result: GitLab will now automatically notify GCP to begin the deployment pipeline whenever a Merge Request is finalized into main.*

---

## 🔌 Option 3: Generic Webhooks (Alternative GitLab approach)

If you have strict security policies and **cannot** grant Google Cloud an API token to your GitLab account, you can use the generic Webhook approach:

1.  In Google Cloud, create a new Trigger but select **Webhook Event** as the Event type.
2.  Google Cloud will generate a unique HTTPS Webhook URL containing a secret key.
3.  Copy this URL.
4.  Go to your GitLab Repository → **Settings** → **Webhooks**.
5.  Paste the Google Cloud URL, select **Push events** targeting the `main` branch, and save.
6.  *Note: You will need to modify your `cloudbuild.yaml` to parse the incoming webhook payload if you want to dynamically extract the exact Git Commit SHA.*
