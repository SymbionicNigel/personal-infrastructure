terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.4.0"
    }
  }
}

resource "linode_domain" "main_site" {
  type       = "master"
  domain     = var.HOSTNAME_TLD
  expire_sec = 0
  soa_email  = var.EMAIL_ADDRESS
  tags       = tolist(var.TAGS)
}

resource "linode_domain_record" "main_site_a_records" {
  for_each = tomap({
    main     = "",
    wildcard = "*"
  })
  domain_id   = linode_domain.main_site.id
  record_type = "A"
  name        = each.value
  target      = var.WEBSITE_INSTANCE_IP
  weight      = 0
  port        = 0
  priority    = 0
  protocol    = null
  service     = null
  ttl_sec     = 0
}
