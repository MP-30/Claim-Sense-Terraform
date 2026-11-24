moved {
  from = aws_ecr_repository.app
  to   = module.foundation.aws_ecr_repository.app
}

moved {
  from = aws_cloudwatch_log_group.app
  to   = module.foundation.aws_cloudwatch_log_group.app
}

moved {
  from = aws_ecs_cluster.main
  to   = module.foundation.aws_ecs_cluster.main
}
