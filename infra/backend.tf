# infra/backend.tf
# Remote state backend using Azure Storage, authenticated via OIDC
# (Workload Identity Federation) — no access keys, no secrets.

terraform {
  backend "azurerm" {
    use_oidc             = true
    use_azuread_auth     = true # Entra ID auth to the blob data plane (recommended over access keys)
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstatevinfo123" # <- replace with output from bootstrap
    container_name       = "tfstate"
    key                  = "infra/terraform.tfstate"
  }
}
