terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstates"
    storage_account_name = "tfstate202509231456"
    container_name       = "tfstate"
    key                  = "microservice-app-example/dev/terraform.tfstate"
  }
}

