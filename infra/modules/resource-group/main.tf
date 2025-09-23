variable "project" { type = string }
variable "environment" { type = string }
variable "location" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  name = "${var.project}-${var.environment}-rg"
}

resource "azurerm_resource_group" "this" {
  name     = local.name
  location = var.location
  tags     = var.tags
}

output "name" { value = azurerm_resource_group.this.name }
output "location" { value = azurerm_resource_group.this.location }

