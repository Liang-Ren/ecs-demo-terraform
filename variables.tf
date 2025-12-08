variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ecs_demo_image" {
  description = "ECR image URI for ECS demo (e.g. 895169747731.dkr.ecr.us-east-1.amazonaws.com/ecs-demo:latest)"
  type        = string
}

variable "ecs_desired_count" {
  description = "How many ECS tasks to run"
  type        = number
  default     = 3
}
