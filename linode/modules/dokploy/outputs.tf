output "instance_ip" {
  value = one(linode_instance.dokploy_main.ipv4)
}
