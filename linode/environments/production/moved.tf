moved {
  from = module.acme_backup.linode_object_storage_key.infra_backups
  to   = linode_object_storage_key.infra_backups
}

moved {
  from = module.acme_backup.null_resource.configure_acme_backup
  to   = module.dokploy-instance.null_resource.configure_acme_backup
}

moved {
  from = module.acme_backup.null_resource.restore_acme
  to   = module.dokploy-instance.null_resource.restore_acme
}

moved {
  from = module.dokploy_dns01.time_rotating.dns_token
  to   = module.dokploy-instance.time_rotating.dns_token
}

moved {
  from = module.dokploy_dns01.terraform_data.dns_token_rotation
  to   = module.dokploy-instance.terraform_data.dns_token_rotation
}

moved {
  from = module.dokploy_dns01.linode_token.dns
  to   = module.dokploy-instance.linode_token.dns
}

moved {
  from = module.dokploy_dns01.null_resource.configure_main
  to   = module.dokploy-instance.null_resource.configure_main
}

moved {
  from = module.dokploy_dns01.null_resource.configure
  to   = module.dokploy-instance.null_resource.configure
}

moved {
  from = module.dokploy_dns01.null_resource.configure_dynamic
  to   = module.dokploy-instance.null_resource.configure_dynamic
}
