# Aurora MySQL Serverless v2 for the Catalog service. Configuration
# (database name, master username, connection string format, schema
# handling) confirmed against Catalog's actual source (README.md and
# repository.go), not guessed - see docs/architecture.md Decisions and
# Verification Log.
#
# Master password uses RDS's native managed-password feature rather than
# a Terraform-generated random_password. AWS generates and stores the
# password directly in Secrets Manager; Terraform never sees, generates,
# or stores the plaintext at any point, including in state. This is the
# strongest option available given Catalog's own code requires a real
# username/password pair (confirmed via repository.go's GORM MySQL DSN
# construction) rather than supporting IAM database authentication.

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-aurora-subnet-group"
  }
}

resource "aws_rds_cluster" "catalog" {
  cluster_identifier = "${var.project_name}-catalog-aurora"
  engine             = "aurora-mysql"
  # "provisioned" is correct for Serverless v2 - "serverless" engine mode
  # is the older Serverless v1 API and does not apply here.
  engine_mode = "provisioned"
  # Minimum version required for Serverless v2 auto-pause (0 ACU minimum
  # capacity) support, confirmed against AWS's Aurora Serverless v2
  # documentation.
  engine_version = "8.0.mysql_aurora.3.08.0"

  database_name   = var.aurora_db_name
  master_username = var.aurora_master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  storage_encrypted = true

  # This is a personal dev/test project torn down between sessions, not a
  # production database. A production version of this infrastructure
  # would not set this.
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-catalog-aurora"
  }
}

resource "aws_rds_cluster_instance" "catalog" {
  cluster_identifier = aws_rds_cluster.catalog.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.catalog.engine
  engine_version       = aws_rds_cluster.catalog.engine_version

  tags = {
    Name = "${var.project_name}-catalog-aurora-instance"
  }
}
