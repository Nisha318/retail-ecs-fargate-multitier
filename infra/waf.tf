# AWS-managed rule groups: Common Rule Set for baseline protection (SQLi,
# XSS, known-bad inputs), plus Known Bad Inputs specifically for the
# Log4Shell / CVE-2021-44228 JNDI lookup pattern. Sized for a personal
# project; a production deployment would likely add rate-based rules and
# additional managed rule groups (e.g. IP reputation) depending on
# observed traffic.
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

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-known-bad-inputs"
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

# WAF logging destination. The log group name MUST start with
# "aws-waf-logs-", this is a hard AWS requirement, not a naming
# convention choice. Encrypted with the same KMS key used for the other
# log groups in this project (see logs.tf).
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name = "${var.project_name}-waf-logs"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  resource_arn            = aws_wafv2_web_acl.alb.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}
