# Schema matches AWS's own ECS Immersion Day CloudFormation reference for the
# carts service (confirmed accurate against that source). Table name uses
# this project's naming convention rather than the workshop's.
resource "aws_dynamodb_table" "carts" {
  name         = "${var.project_name}-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  global_secondary_index {
    name            = "idx_global_customerId"
    hash_key        = "customerId"
    projection_type = "ALL"
  }

  tags = {
    Name = "${var.project_name}-carts"
  }
}
