# AWS-managed Common Rule Set only, for baseline protection (SQLi, XSS,
# known-bad inputs) without hand-authoring custom rules. Sized for a
# personal project; a production deployment would likely add rate-based
# rules and additional managed rule groups (e.g. known bad inputs, IP
# reputation) depending on observed traffic.
#
# Associated with the ALB defined in alb.tf via aws_lb.main.
resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.project_name}-alb-waf"
  scope       = "REGIONAL"
  description = "Baseline managed protection for the public ALB"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-alb-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-alb-waf"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}
