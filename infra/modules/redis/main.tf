variable "project" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  name = "${var.project}-${var.environment}-redis"
}

resource "azurerm_redis_cache" "this" {
  name                = replace(local.name, "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = 1
  family              = "C"
  sku_name            = "Basic"
  minimum_tls_version = "1.2"
  tags                = var.tags
}

output "hostname" { value = azurerm_redis_cache.this.hostname }
output "ssl_port" { value = azurerm_redis_cache.this.ssl_port }
output "primary_key" {
  value     = azurerm_redis_cache.this.primary_access_key
  sensitive = true
}