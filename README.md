# Deploying Azure Infrastructure with Terraform + GitHub Actions (OIDC, No Secrets)

A production-grade starter kit implementing current best practices (2026) for
deploying Azure infrastructure via Terraform, automated with GitHub Actions,
using **Workload Identity Federation (OIDC)** — no client secrets stored anywhere.

## What's inside

```
terraform-azure-github-actions/
├── bootstrap/                     # One-time setup: state storage + App Registration
│   └── main.tf
├── infra/                         # Your actual infrastructure (example)
│   ├── providers.tf
│   ├── backend.tf
│   ├── main.tf
│   └── variables.tf
└── .github/workflows/
    ├── terraform-plan.yml         # Runs on PR -> plan + comment
    └── terraform-apply.yml        # Runs on merge to main -> apply
```

## Step-by-step setup

### 1. Create the Azure App Registration + Federated Credentials (one-time, via CLI)

```bash
APP_NAME="gh-actions-terraform"
GITHUB_ORG="your-org"
GITHUB_REPO="your-repo"

# Create the app registration + service principal
az ad app create --display-name "$APP_NAME"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"

# Assign Contributor at subscription scope (tighten to a resource group in production)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Federated credential for PRs
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "gh-pull-requests",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Federated credential for main branch (apply)
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "gh-main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

This is the officially recommended pattern from Microsoft and GitHub docs — it
eliminates long-lived `ARM_CLIENT_SECRET` values entirely. <cite>turn1search16</cite><cite>turn1search8</cite>

### 2. Create the remote state storage account (do this OUTSIDE your main Terraform state — chicken-and-egg problem otherwise)

Use `bootstrap/main.tf` or plain Azure CLI:

```bash
RG=tfstate-rg
SA=tfstate$RANDOM
az group create --name $RG --location centralindia
az storage account create --resource-group $RG --name $SA --sku Standard_LRS --encryption-services blob
az storage container create --name tfstate --account-name $SA
```

Grant the App Registration `Storage Blob Data Contributor` on this storage account
(data-plane role, needed for Entra ID auth to blob storage). <cite>turn1search21</cite><cite>turn1search13</cite>

### 3. Add GitHub repository secrets (IDs only — never a client secret)

| Secret name             | Value                          |
|--------------------------|--------------------------------|
| `AZURE_CLIENT_ID`         | App registration Client ID     |
| `AZURE_TENANT_ID`         | Directory (tenant) ID           |
| `AZURE_SUBSCRIPTION_ID`   | Subscription ID                 |

No `AZURE_CLIENT_SECRET` is needed with OIDC. <cite>turn1search16</cite>

### 4. Configure the `azurerm` backend to use OIDC

See `infra/backend.tf` — note `use_oidc = true` and `use_azuread_auth = true`.

### 5. Workflows

- `terraform-plan.yml` — triggers on every PR touching `infra/**`, runs
  `fmt -check`, `validate`, and `plan`, then posts the plan as a PR comment.
- `terraform-apply.yml` — triggers on push/merge to `main`, runs `terraform apply -auto-approve`
  (optionally gated behind a GitHub Environment with required reviewers for production).

## Best-practice checklist

- [x] **No secrets stored** — use OIDC / Workload Identity Federation instead of client secrets. <cite>turn1search14</cite>
- [x] **Remote state in Azure Storage** with native blob-lease **state locking**, never local `.tfstate`. <cite>turn1search17</cite><cite>turn1search2</cite>
- [x] **Separate bootstrap state** from application state (avoids the chicken-and-egg problem of Terraform managing its own backend). <cite>turn1search21</cite>
- [x] **Plan on PR, Apply on merge** — plan output posted as a PR comment for human review before anything touches Azure. <cite>turn1search7</cite><cite>turn1search23</cite>
- [x] **Least-privilege RBAC** — scope the service principal/managed identity to a resource group or subscription, not tenant-root, and separate the state storage role (`Storage Blob Data Contributor`) from the deployment role (`Contributor`). <cite>turn1search12</cite>
- [x] **Environments + required reviewers** in GitHub for the `apply` job on production, so a human approves before `terraform apply` runs against prod. <cite>turn1search20</cite>
- [x] **Pin action & provider versions** (`azure/login@v2`, `hashicorp/setup-terraform@v3`, `azurerm ~> 3.0` or `~> 4.0`) to avoid unexpected breaking changes.
- [x] **Static analysis / policy checks** — run `terraform fmt -check`, `terraform validate`, and a scanner like `checkov` or `tfsec` in CI before plan. <cite>turn1search10</cite>
- [x] **Separate repos/dirs per environment** (dev/stage/prod) or use workspaces + distinct `tfvars` and state keys, never share one state file across environments.
- [x] **Drift detection** — a scheduled workflow running `terraform plan` periodically to catch manual/out-of-band changes. <cite>turn1search10</cite>
- [x] **Minimal permissions block** in each workflow job: `id-token: write`, `contents: read`, `pull-requests: write` only where needed. <cite>turn1search7</cite>

## References
- Microsoft Learn – Authenticate to Azure from GitHub Actions using OIDC <cite>turn1search16</cite>
- Microsoft Learn – Store Terraform state in Azure Storage <cite>turn1search2</cite>
- GitHub Docs – Configuring OpenID Connect in Azure <cite>turn1search8</cite>
- HashiCorp Developer – `azurerm` backend authentication methods <cite>turn1search13</cite>
- Azure-Samples/github-terraform-oidc-ci-cd (official Microsoft sample) <cite>turn1search20</cite>
- Azure-Samples/terraform-github-actions (reference plan/apply pipeline) <cite>turn1search10</cite>
