locals {
  common_tags = merge({
    Project     = var.project,
    Environment = var.environment
  }, var.tags)
}

module "resource_group" {
  source      = "./modules/resource-group"
  project     = var.project
  environment = var.environment
  location    = var.location
  tags        = local.common_tags
}

module "acr" {
  source      = "./modules/acr"
  project     = var.project
  environment = var.environment
  location    = var.location
  sku         = var.acr_sku
  tags        = local.common_tags
  resource_group_name = module.resource_group.name
}

module "redis" {
  source              = "./modules/redis"
  project             = var.project
  environment         = var.environment
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

module "aca" {
  source                 = "./modules/aca"
  project                = var.project
  environment            = var.environment
  location               = var.location
  resource_group_name    = module.resource_group.name
  acr_name               = module.acr.name
  acr_login_server       = module.acr.login_server
  jwt_secret             = var.jwt_secret
  redis_hostname         = module.redis.hostname
  redis_ssl_port         = module.redis.ssl_port
  redis_primary_key      = module.redis.primary_key
  tags                   = local.common_tags
}

