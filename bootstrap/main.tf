# bootstrap/main.tf
# Run this ONCE, locally (az login) or via a separate manual pipeline,
# to create the storage account that will hold Terraform remote state
# for everything else. Do NOT let your main infra state manage this —
# it creates a chicken-and-egg problem.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # This bootstrap config itself can stay local, or be pushed once
  # to a separate "bootstrap" container after the fact.
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate"
  location = "centralindia"
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "tfstate${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true # protects against accidental state corruption
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "resource_group_name" {
  value = azurerm_resource_group.tfstate.name
}

output "container_name" {
  value = azurerm_storage_container.tfstate.name
}
