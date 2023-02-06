resource "linode_domain" "symbionicDomain" {
  type = "master"
  domain = "symbionic.tech"
  soa_email = "nphilmont2010@gmail.com"
}

resource "linode_domain_record" "flaskTest" {
  for_each = set("symbionic.tech", "*.symbionic.tech")
  domain_id = linode_domain.symbionicDomain.id
  record_type = "A"
  name = each.key
  target = linode_instance.fedora-test.private_ip_address
}

resource "linode_domain_record" "symbionic_NS_records" {
  for_each = range(5)
  domain_id = linode_domain.symbionicDomain.id
  record_type = "NS"
  name = format("ns%s.linode.com", each.key)
  target = "symbionic.tech"
}