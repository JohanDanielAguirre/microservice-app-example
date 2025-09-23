output "region" {
  value = var.location
}

output "resource_group_name" {
  value = module.resource_group.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "frontend_url" {
  value = module.aca.frontend_url
}
