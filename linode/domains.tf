
resource "linode_domain" "symbionic_tech" {
  type = "master"
  domain = "symbionic.tech"
  expire_sec = 0
  soa_email = "nphilmont2010@gmail.com"
}

resource "linode_domain_record" "symbionic_a_records" {
  for_each = tomap({
    symbionic = "",
    widcard=  "*"
  })
  domain_id = linode_domain.symbionic_tech.id
  record_type = "A"
  name = each.value
  target = "172.234.27.65"
  weight = 0
  port = 0
  priority = 0
  protocol = null
  service = null
  ttl_sec = 0
}