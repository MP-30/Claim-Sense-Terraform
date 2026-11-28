variable "worker_image_tag" {
  description = "Published Lambda image tag. Null keeps synchronous upload processing."
  type        = string
  default     = null
}

locals {
  worker_enabled = local.app_enabled && var.worker_image_tag != null
  worker_name    = "claimsense-local-worker"
  worker_timeout = 600
}

resource "aws_sqs_queue" "processing_dead_letter" {
  count                      = local.worker_enabled ? 1 : 0
  name                       = "claimsense-local-processing-dlq"
  visibility_timeout_seconds = local.worker_timeout * 6
  message_retention_seconds  = 1209600
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue" "processing" {
  count                      = local.worker_enabled ? 1 : 0
  name                       = "claimsense-local-processing"
  visibility_timeout_seconds = local.worker_timeout * 6
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dead_letter[0].arn
    maxReceiveCount     = 3
  })
}

resource "aws_iam_role_policy" "enqueue" {
  count = local.worker_enabled ? 1 : 0
  name  = "enqueue-claim-processing"
  role  = aws_iam_role.task[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.processing[0].arn
    }]
  })
}

resource "aws_iam_role" "worker" {
  count = local.worker_enabled ? 1 : 0
  name  = local.worker_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "worker" {
  count             = local.worker_enabled ? 1 : 0
  name              = "/aws/lambda/${local.worker_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "worker" {
  count = local.worker_enabled ? 1 : 0
  name  = "claim-processing"
  role  = aws_iam_role.worker[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.processing[0].arn, aws_sqs_queue.processing_dead_letter[0].arn]
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${module.foundation.documents_bucket_arn}/uploads/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = module.foundation.documents_bucket_arn
        Condition = {
          StringLike = { "s3:prefix" = "uploads/*" }
        }
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_db_instance.app[0].master_user_secret[0].secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.worker[0].arn}:*"
      },
      ], local.parameter_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = local.parameter_arn
    }])
  })
}

resource "aws_lambda_function" "worker" {
  count         = local.worker_enabled ? 1 : 0
  function_name = local.worker_name
  role          = aws_iam_role.worker[0].arn
  package_type  = "Image"
  image_uri     = "${module.foundation.ecr_repository_url}:${var.worker_image_tag}"
  timeout       = local.worker_timeout
  memory_size   = 1536

  environment {
    variables = merge({
      AWS_ENDPOINT_URL_S3        = "http://s3.localhost.localstack.cloud:4566"
      CLAIMS_DOCUMENTS_BUCKET    = module.foundation.documents_bucket
      CLAIMS_DATABASE_SECRET_ARN = aws_db_instance.app[0].master_user_secret[0].secret_arn
      CLAIMS_PROCESSING_DLQ_ARN  = aws_sqs_queue.processing_dead_letter[0].arn
      POSTGRES_HOST              = aws_db_instance.app[0].address
      POSTGRES_PORT              = tostring(aws_db_instance.app[0].port)
      POSTGRES_USER              = aws_db_instance.app[0].username
      POSTGRES_DB                = aws_db_instance.app[0].db_name
      }, var.openai_parameter_name == null ? {} : {
      CLAIMS_OPENAI_PARAMETER = var.openai_parameter_name
      }, var.openai_model == null ? {} : {
      OPENAI_MODEL = var.openai_model
    })
  }

  depends_on = [aws_iam_role_policy.worker]
}

resource "aws_lambda_event_source_mapping" "processing" {
  count            = local.worker_enabled ? 1 : 0
  event_source_arn = aws_sqs_queue.processing[0].arn
  function_name    = aws_lambda_function.worker[0].arn
  batch_size       = 1

  scaling_config {
    maximum_concurrency = 2
  }
}

resource "aws_lambda_event_source_mapping" "processing_dead_letter" {
  count            = local.worker_enabled ? 1 : 0
  event_source_arn = aws_sqs_queue.processing_dead_letter[0].arn
  function_name    = aws_lambda_function.worker[0].arn
  batch_size       = 1
}

output "worker_name" {
  value = local.worker_enabled ? aws_lambda_function.worker[0].function_name : null
}

output "processing_queue_url" {
  value = local.worker_enabled ? aws_sqs_queue.processing[0].url : null
}
