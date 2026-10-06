# --- DNS ---
#
# One A record pointing var.dns_name at the Elastic IP, so the name follows the
# address. Every destroy/recreate cycle allocates a fresh EIP, and the deploy
# cannot start until the name resolves to it: the tls role validates over
# HTTP-01 and the smoke test fetches the site by name. Without this the record
# is a manual step between tf-apply and deploy, every single time.
#
# Created only when dns_name is set. Production leaves it empty until cutover,
# because its name is the apex and the apex serves the live site from another
# host until then — see envs/production/main.tf.

# Looked up, not managed: the zone is shared by both environments and carries
# the mail records too, so it has to outlive any one environment's destroy.
data "aws_route53_zone" "this" {
  count = var.dns_name == "" ? 0 : 1
  name  = var.dns_zone
}

resource "aws_route53_record" "wordpress" {
  count = var.dns_name == "" ? 0 : 1

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.dns_name
  type    = "A"
  records = [aws_eip.wordpress.public_ip]

  # Short on purpose. A rebuild changes the address and the deploy follows the
  # apply, so this bounds how long a resolver can keep handing out the old one.
  ttl = 60

  # Production's apex record already exists — made by hand, pointing at the old
  # host. This lets the first apply with dns_name set take it over in place
  # rather than fail on "already exists" and need an import. It does not make
  # later manual edits stick: the next apply puts the record back.
  allow_overwrite = true
}
