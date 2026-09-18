# infra/main.tf
# Minimal example resource - replace with your actual infrastructure.
# test1
resource "azurerm_resource_group" "this" {
  name     = "rg-${var.environment}-example"
  location = var.location

  tags = {
    environment = var.environment
    managed_by  = "terraform"
  }
}
