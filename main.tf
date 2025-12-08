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

# ------------ 基础网络：用默认 VPC 和子网，方便实验 ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ------------ CloudWatch 日志组 ----------
resource "aws_cloudwatch_log_group" "ecs_demo" {
  name              = "/ecs/ecs-demo"
  retention_in_days = 14
}

# ------------ ECS Cluster（港口群）+ 开启 Container Insights ----------
resource "aws_ecs_cluster" "ecs_demo" {
  name = "ecs-demo-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ------------ IAM Role：Task 执行角色（拉镜像 & 写日志） ----------
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

# 附加 AWS 托管策略：拉 ECR + 写 CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ------------ ALB + Target Group + Listener（对外入口） ----------
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

# ------------ ECS Service 的 SG（任务本身） ----------
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

# ------------ ECS Task Definition（船的设计图） ----------
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

# ------------ ECS Service（港务局，调度 N 条船） ----------
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
    ignore_changes = [desired_count] # 手动调节时不想频繁刷新
  }

  depends_on = [aws_lb_listener.ecs_demo_http]
}
