variable "project" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "acr_name" { type = string }
variable "acr_login_server" { type = string }
variable "jwt_secret" { type = string }
variable "redis_hostname" { type = string }
variable "redis_ssl_port" { type = number }
variable "redis_primary_key" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  env_name = "${var.project}-${var.environment}-acaenv"
}

resource "azurerm_container_app_environment" "env" {
  name                         = local.env_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  infrastructure_subnet_id     = null
  tags                         = var.tags
}

resource "azurerm_user_assigned_identity" "aca" {
  name                = "${var.project}-${var.environment}-aca-mi"
  resource_group_name = var.resource_group_name
  location            = var.location
}

locals {
  images = {
    auth     = "${var.acr_login_server}/microservice-app-example-auth-api:latest"
    users    = "${var.acr_login_server}/microservice-app-example-users-api:latest"
    todos    = "${var.acr_login_server}/microservice-app-example-todos-api:latest"
    logger   = "${var.acr_login_server}/microservice-app-example-log-message-processor:latest"
    frontend = "${var.acr_login_server}/microservice-app-example-frontend:latest"
  }
}

resource "azurerm_container_app" "users_api" {
  name                         = "msapp-${var.environment}-users"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }
  template {
    container {
      name   = "users-api"
      image  = local.images.users
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "SERVER_PORT"
        value = "8083"
      }
      env {
        name  = "SPRING_ZIPKIN_BASEURL"
        value = ""
      }
    }
    http_scale_rule {
      name = "httpscale"
      concurrent_requests = 50
    }
  }
  ingress {
    external_enabled = false
    target_port      = 8083
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.aca.id
  }
}

resource "azurerm_container_app" "auth_api" {
  name                         = "msapp-${var.environment}-auth"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }
  template {
    container {
      name   = "auth-api"
      image  = local.images.auth
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "AUTH_API_PORT"
        value = "8000"
      }
      env {
        name  = "USERS_API_ADDRESS"
        value = "http://msapp-${var.environment}-users"  # ✅ URL interna
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
    }
  }
  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.aca.id
  }
}

resource "azurerm_container_app" "todos_api" {
  name                         = "msapp-${var.environment}-todos"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }
  template {
    container {
      name   = "todos-api"
      image  = local.images.todos
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "TODO_API_PORT"
        value = "8082"
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "REDIS_URL"
        value = "rediss://${var.redis_hostname}:${var.redis_ssl_port}"
      }
      env {
        name  = "REDIS_PASSWORD"
        value = var.redis_primary_key
      }
      env {
        name  = "REDIS_USE_TLS"
        value = "true"
      }
    }
  }
  ingress {
    external_enabled = true
    target_port      = 8082
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.aca.id
  }
}

resource "azurerm_container_app" "logger" {
  name                         = "msapp-${var.environment}-logger"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }
  template {
    container {
      name   = "log-message-processor"
      image  = local.images.logger
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "REDIS_URL"
        value = "rediss://${var.redis_hostname}:${var.redis_ssl_port}"
      }
      env {
        name  = "REDIS_PASSWORD"
        value = var.redis_primary_key
      }
      env {
        name  = "REDIS_USE_TLS"
        value = "true"
      }
    }
  }
  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.aca.id
  }
}

resource "azurerm_container_app" "frontend" {
  name                         = "msapp-${var.environment}-frontend"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }
  template {
    container {
      name   = "frontend"
      image  = local.images.frontend
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "AUTH_API_ADDRESS"
        value = "https://msapp-${var.environment}-auth.${azurerm_container_app_environment.env.default_domain}"
      }
      env {
        name  = "TODOS_API_ADDRESS"
        value = "https://msapp-${var.environment}-todos.${azurerm_container_app_environment.env.default_domain}"
      }
    }
  }
  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.aca.id
  }
}

output "frontend_url" {
  value = azurerm_container_app.frontend.latest_revision_fqdn
}

data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}