variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "ecs_demo_image" {
  description = "ECR image URI for ECS demo (e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com/ecs-demo:latest)"
  type        = string
}

variable "ecs_desired_count" {
  description = "How many ECS tasks to run"
  type        = number
  default     = 2
}
