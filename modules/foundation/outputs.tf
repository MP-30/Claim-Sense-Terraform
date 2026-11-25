output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "documents_bucket" {
  value = aws_s3_bucket.documents.id
}

output "documents_bucket_arn" {
  value = aws_s3_bucket.documents.arn
}
