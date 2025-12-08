terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ------------ Network: default VPC & Subnets ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ------------ CloudWatch log group ----------
resource "aws_cloudwatch_log_group" "ecs_demo" {
  name              = "/ecs/ecs-demo"
  retention_in_days = 14
}

# ------------ ECS Cluster + enable Container Insights ----------
resource "aws_ecs_cluster" "ecs_demo" {
  name = "ecs-demo-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ------------ IAM Role: Task assumes the role ----------
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "ecs-demo-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

# AWS managed policy: ECR + CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ------------ ALB + Target Group + Listener ----------
resource "aws_security_group" "alb_sg" {
  name        = "ecs-demo-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "ecs_demo" {
  name               = "ecs-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "ecs_demo" {
  name        = "ecs-demo-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "ecs_demo_http" {
  load_balancer_arn = aws_lb.ecs_demo.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    target_group_arn = aws_lb_target_group.ecs_demo.arn
  }
}

# ------------ ECS Service SG ----------
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "ecs-demo-tasks-sg"
  description = "Allow ALB to reach ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------ ECS Task Definition ----------
resource "aws_ecs_task_definition" "ecs_demo" {
  family                   = "ecs-demo-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "ecs-demo-container"
      image     = var.ecs_demo_image
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_demo.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs-demo"
        }
      }
    }
  ])
}

# ------------ ECS Service ----------
resource "aws_ecs_service" "ecs_demo" {
  name            = "ecs-demo-service"
  cluster         = aws_ecs_cluster.ecs_demo.id
  task_definition = aws_ecs_task_definition.ecs_demo.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_demo.arn
    container_name   = "ecs-demo-container"
    container_port   = 8080
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.ecs_demo_http]
}

resource "aws_cloudwatch_log_metric_filter" "ecs_errors" {
  name           = "ecs-demo-error-count"
  log_group_name = aws_cloudwatch_log_group.ecs_demo.name

  pattern = "\"ERROR\""

  metric_transformation {
    name      = "EcsDemoErrorCount"
    namespace = "ECS/DemoApp"
    value     = "1"
  }
}

resource "aws_sns_topic" "security_alerts" {
  name = "ecs-security-alerts"
}

resource "aws_cloudwatch_metric_alarm" "ecs_error_alarm" {
  alarm_name          = "ECS-Demo-High-Error-Rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.ecs_errors.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.ecs_errors.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 5

  alarm_description = "More than 5 ERROR logs in 1 minute in ECS demo app"
  alarm_actions     = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "ECS-Demo-CPU-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  alarm_description = "ECS demo service CPU > 80% for 2 min"
  alarm_actions     = [aws_sns_topic.security_alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_demo.name
    ServiceName = aws_ecs_service.ecs_demo.name
  }
}

resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "guardduty-high-severity"
  description = "Forward high severity GuardDuty findings to SNS"
  event_pattern = jsonencode({
    "source"      : ["aws.guardduty"],
    "detail-type" : ["GuardDuty Finding"],
    "detail" : {
      "severity" : [
        { "numeric" : [">=", 7] }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

# EventBridge  to SNS 
resource "aws_iam_role" "events_to_sns_role" {
  name = "events-to-sns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "events_to_sns_policy" {
  role = aws_iam_role.events_to_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.security_alerts.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns_with_role" {
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "send-to-sns-with-role"
  arn       = aws_sns_topic.security_alerts.arn
  role_arn  = aws_iam_role.events_to_sns_role.arn
}