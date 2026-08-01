# IAM role assumed by this project's GitHub Actions pipeline (via OIDC),
# scoped to read-only access on exactly the two ECR repos this project
# owns, so CI can pull and scan the private mirror images instead of
# scanning public.ecr.aws source images that differ from what's actually
# deployed.
#
# Uses a DATA SOURCE for the OIDC provider, not a resource. The GitHub
# Actions OIDC provider (token.actions.githubusercontent.com) is an
# account-level IAM resource - AWS allows only one per account, and this
# account almost certainly already has one from other projects' pipelines
# (see container-security-progression). Creating a second one here would
# fail with an EntityAlreadyExists error. If this data source fails to
# find one, that means no project in this account has set up GitHub OIDC
# yet, and the provider needs to be created once, manually or via
# whichever project sets it up first - not duplicated per-project.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions_ecr" {
  name = "${var.project_name}-gha-ecr-readonly"

  # Subject condition scoped to this exact repo, main branch only, so no
  # other repo (including forks) can assume this role even if they somehow
  # obtained a token from the same OIDC provider. GitHub sends the
  # username in lowercase in the actual token regardless of profile
  # display casing - the condition must match that, not the display name.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:nisha318/retail-ecs-fargate-multitier:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-gha-ecr-readonly"
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "${var.project_name}-gha-ecr-readonly-policy"
  role = aws_iam_role.github_actions_ecr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ecr:GetAuthorizationToken is an account-level action and does
        # not support resource-level scoping - AWS requires Resource: "*"
        # for it specifically, even in an otherwise tightly-scoped policy.
        Sid      = "GetAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PullSpecificRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          aws_ecr_repository.ui.arn,
          aws_ecr_repository.cart.arn
        ]
      }
    ]
  })
}
