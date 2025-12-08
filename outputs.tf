output "alb_dns_name" {
  description = "Public ALB DNS; open http://this to see the demo"
  value       = aws_lb.ecs_demo.dns_name
}
