# Fix for F-03 — aws_db_instance.default in terraform/aws/db-app.tf has
# storage_encrypted = false AND publicly_accessible = true set simultaneously,
# with no backup retention and no KMS key. This is the corrected resource definition.
#
# NOTE (operational): storage_encrypted cannot be toggled on an existing running RDS
# instance in place. This requires a snapshot -> encrypted-copy -> restore-into-new-instance
# cutover, scheduled as a maintenance window per remediation-advisory.md, not a direct apply
# against production.

resource "aws_kms_key" "rds_key" {
  description             = "CMK for RDS encryption at rest - workload-id=web-app-db"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    workload-id          = "web-app-db"
    data-classification  = "restricted"
  }
}

resource "aws_db_instance" "default" {
  name                   = var.dbname
  engine                 = "mysql"
  option_group_name      = aws_db_option_group.default.name
  parameter_group_name   = aws_db_parameter_group.default.name
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  identifier        = "rds-${local.resource_prefix.value}"
  engine_version     = "8.0"
  instance_class      = "db.t3.micro"
  allocated_storage    = "20"
  username        = "admin"
  password        = var.password
  apply_immediately     = false # avoid unplanned downtime; changes apply in the next maintenance window
  multi_az        = true    # F-25 fix: no recoverability path previously existed at all
  backup_retention_period = 14    # F-25 fix: was 0
  storage_encrypted     = true    # F-03/F-07 fix
  kms_key_id        = aws_kms_key.rds_key.arn
  skip_final_snapshot    = false   # F-25 fix: a final snapshot is now taken on deletion
  final_snapshot_identifier = "rds-${local.resource_prefix.value}-final"
  monitoring_interval    = 60    # basic enhanced monitoring, feeds Module 6 telemetry
  publicly_accessible    = false   # F-03 fix: no longer reachable from the public internet

  tags = merge({
    Name        = "${local.resource_prefix.value}-rds"
    Environment = local.resource_prefix.value
    workload-id = "web-app-db"
  })

  lifecycle {
    ignore_changes = ["password"]
  }
}

# F-15 fix: the RDS security group previously allowed unrestricted egress to 0.0.0.0/0.
# Scoped down to nothing - a database has no legitimate reason to initiate outbound
# connections beyond provider-managed backup/replication traffic, which does not route
# through this security group's egress rule at all.
resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [] # was ["0.0.0.0/0"]
  self              = true
  security_group_id = aws_security_group.default.id
}
