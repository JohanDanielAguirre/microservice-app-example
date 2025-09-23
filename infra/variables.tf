variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "microservice-app-example"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "location" {
  description = "Azure location (e.g., eastus)"
  type        = string
}

variable "acr_sku" {
  description = "ACR SKU: Basic, Standard, Premium"
  type        = string
  default     = "Standard"
}

variable "jwt_secret" {
  description = "JWT secret used by services"
  type        = string
  sensitive   = true
}

