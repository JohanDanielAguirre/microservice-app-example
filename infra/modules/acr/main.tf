variable "project" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }

variable "sku" {
  type    = string
  default = "Standard"
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  name = replace("${var.project}${var.environment}acr", "-", "")
}

resource "azurerm_container_registry" "this" {
  name                = substr(local.name, 0, 50)
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}

output "login_server" { value = azurerm_container_registry.this.login_server }
output "id" { value = azurerm_container_registry.this.id }
output "name" { value = azurerm_container_registry.this.name }

