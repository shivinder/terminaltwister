# --- DNS ---
#
# One A record pointing var.dns_name at the Elastic IP, so the name follows the
# address. Every destroy/recreate cycle allocates a fresh EIP, and the deploy
# cannot start until the name resolves to it: the smoke test fetches the site
# by name, and the deploy job checks the record first. Without this the record
# is a manual step between tf-apply and deploy, every single time.
#
# Created only when dns_name is set. Production leaves it empty until cutover,
# because its name is the apex and the apex serves the live site from another
# host until then — see envs/production/main.tf.
#
# The certificate does not depend on this record. The tls role validates over
# DNS-01, through the _acme-challenge records iam.tf lets the instance write.

# Looked up, not managed: the zone is shared by both environments and carries
# the mail records too, so it has to outlive any one environment's destroy.
# Needed by the A record below and by the challenge-record policy in iam.tf.
data "aws_route53_zone" "this" {
  count = var.dns_name != "" || length(var.certificate_names) > 0 ? 1 : 0
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
