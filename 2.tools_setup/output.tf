output "nameservers" {
  value = <<-EOF
Please update your DNS nameservers to:

${join("\n", [for ns in google_dns_managed_zone.project.name_servers : trimsuffix(ns, ".")])}
EOF
}