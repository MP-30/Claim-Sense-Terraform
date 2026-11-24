variable "image_tag" {
  description = "Published LocalStack ECR image tag. Leave null to provision only the foundation."
  type        = string
  default     = null
}

variable "openai_parameter_name" {
  description = "Optional name of an existing LocalStack SSM SecureString for the OpenAI API key."
  type        = string
  default     = null
}

variable "openai_model" {
  description = "Optional model override for the LocalStack API. Null uses the application default."
  type        = string
  default     = null
}

locals {
  app_enabled = var.image_tag != null
  data_root   = pathexpand("~/.cache/claimsense-ecs")
  api_port    = 18000
  portal_port = 18501
  db_environment = [
    { name = "POSTGRES_USER", value = "claimsense" },
    { name = "POSTGRES_DB", value = "claimsense" },
    { name = "POSTGRES_PASSWORD", value = "claimsense_local_demo" }
  ]
  parameter_arn = var.openai_parameter_name == null ? null : "arn:aws:ssm:ap-south-1:000000000000:parameter${var.openai_parameter_name}"
  launcher      = abspath("${path.module}/../../scripts/start-local-ecs.py")
  launcher_mounts = [
    { sourceVolume = "task-addresses", containerPath = "/run/claimsense" },
    { sourceVolume = "launcher", containerPath = "/app/start-local-ecs.py", readOnly = true }
  ]
}

data "aws_vpc" "default" {
  count   = local.app_enabled ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = local.app_enabled ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

resource "aws_iam_role" "execution" {
  count = local.app_enabled ? 1 : 0
  name  = "claimsense-local-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  count      = local.app_enabled ? 1 : 0
  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "openai" {
  count = local.app_enabled && local.parameter_arn != null ? 1 : 0
  name  = "read-openai-key"
  role  = aws_iam_role.execution[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameters"
      Resource = local.parameter_arn
    }]
  })
}

resource "aws_ecs_task_definition" "app" {
  count                    = local.app_enabled ? 1 : 0
  family                   = "claimsense-local"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.execution[0].arn

  volume {
    name      = "database"
    host_path = "${local.data_root}/postgres"
  }

  volume {
    name      = "documents"
    host_path = "${local.data_root}/data"
  }

  volume {
    name      = "task-addresses"
    host_path = "${local.data_root}/run"
  }

  volume {
    name      = "launcher"
    host_path = local.launcher
  }

  container_definitions = jsonencode([
    {
      name        = "db"
      image       = "postgres:18"
      essential   = true
      environment = local.db_environment
      entryPoint  = ["sh", "-ec"]
      command = [<<-EOT
        rm -f /run/claimsense/api /run/claimsense/db
        hostname -i > /run/claimsense/db.tmp
        mv /run/claimsense/db.tmp /run/claimsense/db
        exec docker-entrypoint.sh postgres
      EOT
      ]
      mountPoints = [
        { sourceVolume = "database", containerPath = "/var/lib/postgresql" },
        { sourceVolume = "task-addresses", containerPath = "/run/claimsense" }
      ]
      healthCheck = { command = ["CMD", "pg_isready", "-h", "127.0.0.1", "-U", "claimsense", "-d", "claimsense"], interval = 5, timeout = 3, retries = 6, startPeriod = 10 }
    },
    {
      name      = "api"
      image     = "${module.foundation.ecr_repository_url}:${var.image_tag}"
      essential = true
      command   = ["python", "/app/start-local-ecs.py", "api", tostring(local.api_port), tostring(local.portal_port)]
      environment = concat(local.db_environment, var.openai_model == null ? [] : [
        { name = "OPENAI_MODEL", value = var.openai_model }
      ])
      secrets      = local.parameter_arn == null ? [] : [{ name = "OPENAI_API_KEY", valueFrom = local.parameter_arn }]
      mountPoints  = concat(local.launcher_mounts, [{ sourceVolume = "documents", containerPath = "/app/data" }])
      dockerLabels = { "claimsense.launcher" = filesha256(local.launcher) }
      dependsOn    = [{ containerName = "db", condition = "HEALTHY" }]
      portMappings = [{ containerPort = local.api_port, hostPort = local.api_port, protocol = "tcp" }]
      healthCheck  = { command = ["CMD", "python", "-c", "from urllib.request import urlopen; urlopen('http://127.0.0.1:${local.api_port}/health', timeout=3).close()"], interval = 5, timeout = 4, retries = 6, startPeriod = 10 }
    },
    {
      name         = "ui"
      image        = "${module.foundation.ecr_repository_url}:${var.image_tag}"
      essential    = true
      command      = ["python", "/app/start-local-ecs.py", "ui", tostring(local.api_port), tostring(local.portal_port)]
      mountPoints  = local.launcher_mounts
      dependsOn    = [{ containerName = "api", condition = "HEALTHY" }]
      portMappings = [{ containerPort = local.portal_port, hostPort = local.portal_port, protocol = "tcp" }]
    }
  ])
}

resource "aws_ecs_service" "app" {
  count                              = local.app_enabled ? 1 : 0
  name                               = "claimsense-local"
  cluster                            = module.foundation.cluster_arn
  task_definition                    = aws_ecs_task_definition.app[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets = data.aws_subnets.default[0].ids
  }

  depends_on = [aws_iam_role_policy_attachment.execution, aws_iam_role_policy.openai]
}

output "portal_url" {
  value = local.app_enabled ? "http://127.0.0.1:${local.portal_port}/" : null
}

output "api_url" {
  value = local.app_enabled ? "http://127.0.0.1:${local.api_port}" : null
}
