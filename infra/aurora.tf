# Aurora MySQL Serverless v2 for the Catalog service. Configuration
# (database name, master username, connection string format, schema
# handling) confirmed against Catalog's actual source (README.md and
# repository.go), not guessed - see docs/DECISIONS.md.
#
# Master password is Terraform-generated (random_password, special =
# false), NOT RDS's native managed-password feature. This is a deliberate
# reversal of the original design, documented in DECISIONS.md as its own
# ADR: AWS's managed password generator guarantees at least one
# punctuation character in every password, with no way to exclude
# specific ones. Catalog's connection code (repository.go) builds its
# MySQL DSN with plain string formatting, no escaping, so a password
# containing ")" or "?" (both structurally significant in a MySQL DSN)
# corrupts the connection string outright. This isn't rare bad luck, it's
# guaranteed to happen eventually given AWS's own generation rules. The
# tradeoff: the plaintext password now exists in Terraform state, and
# Aurora loses AWS's free automatic rotation. Same pattern already used
# for Redis's AUTH token (elasticache.tf), for the same reason.

resource "random_password" "aurora_master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "aurora_master" {
  name = "${var.project_name}-aurora-master-credentials"

  # See the identical setting on redis_writer_url/redis_reader_url
  # (elasticache.tf) for why: Secrets Manager's default 30-day recovery
  # window blocks creating a same-named secret on the next apply after a
  # teardown. Fixed here preemptively, confirmed the hard way on the
  # Redis secrets first.
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-aurora-master-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = aws_secretsmanager_secret.aurora_master.id
  secret_string = jsonencode({
    username = var.aurora_master_username
    password = random_password.aurora_master.result
  })
}

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
  master_password = random_password.aurora_master.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  storage_encrypted = true

  # CloudWatch log exports. Cheap (standard CloudWatch Logs ingestion
  # cost) and directly useful given how much of this project's debugging
  # has relied on real logs rather than assumptions. "audit" is
  # intentionally omitted - it requires a custom DB cluster parameter
  # group not otherwise needed here.
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  copy_tags_to_snapshot = true

  # This is a personal dev/test project torn down between sessions, not a
  # production database. A production version of this infrastructure
  # would not set this.
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-catalog-aurora"
  }
}

resource "aws_rds_cluster_instance" "catalog" {
  cluster_identifier         = aws_rds_cluster.catalog.id
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.catalog.engine
  engine_version             = aws_rds_cluster.catalog.engine_version
  auto_minor_version_upgrade = true

  # Free tier (7-day retention, the default) covers this at no extra
  # cost, and would have been genuinely useful during tonight's
  # debugging session for query-level visibility beyond what the
  # application's own logs showed.
  performance_insights_enabled = true

  tags = {
    Name = "${var.project_name}-catalog-aurora-instance"
  }
}
