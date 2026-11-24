output "ecr_repository_url" {
  value = module.foundation.ecr_repository_url
}

output "cluster_name" {
  value = module.foundation.cluster_name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "log_group" {
  value = module.foundation.log_group
}

output "documents_bucket" {
  value = module.foundation.documents_bucket
}
