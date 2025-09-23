terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }

}

provider "azurerm" {
  features {}
  subscription_id = "454e8f57-84c6-40bf-b9e9-4ea02211c975"
}

