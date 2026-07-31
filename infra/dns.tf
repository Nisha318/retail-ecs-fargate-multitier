locals {
  site_fqdn = "${var.site_subdomain}.${var.hosted_zone_domain}"
}

data "aws_route53_zone" "main" {
  name         = var.hosted_zone_domain
  private_zone = false
}

resource "aws_acm_certificate" "site" {
  domain_name       = local.site_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}

# DNS validation record(s). ACM may require more than one record depending
# on the certificate, so this iterates over whatever it asks for rather
# than assuming exactly one.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# Final alias record pointing the subdomain at the ALB. This only resolves
# correctly once the ALB + HTTPS listener exist, but OpenTofu's dependency
# graph handles that ordering automatically - no manual sequencing needed
# at apply time.
resource "aws_route53_record" "site" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.site_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
