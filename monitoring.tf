# monitoring.tf

# -------------------------
# CloudWatch EC2 CPU Alarm
# -------------------------
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "paas-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Alarm if EC2 CPU > ${var.cpu_alarm_threshold}%"

  alarm_actions = []
}

# -------------------------
# CloudWatch EC2 Status Check Alarm
# -------------------------
resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "paas-ec2-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Alarm if EC2 status check fails"

  alarm_actions = []
}

# -------------------------
# CloudWatch RDS CPU Alarm
# -------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "paas-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Alarm if RDS CPU > ${var.cpu_alarm_threshold}%"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }

  alarm_actions = []
}

# -------------------------
# CloudWatch Log Groups 
# -------------------------
resource "aws_cloudwatch_log_group" "k8s_master" {
  name              = "/aws/eks/paas-cluster/master"
  retention_in_days = 7

  tags = {
    Name = "paas-k8s-master-logs"
  }
}

resource "aws_cloudwatch_log_group" "k8s_worker" {
  name              = "/aws/eks/paas-cluster/worker"
  retention_in_days = 7

  tags = {
    Name = "paas-k8s-worker-logs"
  }
}

resource "aws_cloudwatch_log_group" "paas_apps" {
  name              = "/aws/paas/applications"
  retention_in_days = 7

  tags = {
    Name = "paas-applications-logs"
  }
}

# -------------------------
# CloudWatch Custom Metrics from Kubernetes
# -------------------------
resource "aws_cloudwatch_metric_alarm" "k8s_node_memory_high" {
  alarm_name          = "paas-k8s-node-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "Alarm if K8s node memory > ${var.memory_alarm_threshold}%"

  alarm_actions = []
}

# -------------------------
# Essential Scaling Alarms
# -------------------------
resource "aws_cloudwatch_metric_alarm" "master_cpu_high" {
  alarm_name          = "paas-master-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Master CPU > 80% - consider scaling"

  alarm_actions = []
}

resource "aws_cloudwatch_metric_alarm" "worker_spot_interruption" {
  alarm_name          = "paas-worker-spot-interruption"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SpotInstanceInterruptionRate"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Worker spot interruption detected"

  alarm_actions = []
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "paas-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS connections > 80%"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }

  alarm_actions = []
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "paas-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "ALB 5xx errors > 5%"

  dimensions = {
    LoadBalancer = aws_lb.paas_alb.arn_suffix
  }

  alarm_actions = []
}

resource "aws_cloudwatch_metric_alarm" "master_disk_low" {
  alarm_name          = "paas-master-disk-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DiskSpaceUtilization"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Master disk space < 20%"

  alarm_actions = []
}
