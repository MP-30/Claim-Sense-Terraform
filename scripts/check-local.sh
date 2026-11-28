#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_EC2_METADATA_DISABLED=true AWS_PAGER=""
unset AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE

local_aws() {
  aws --endpoint-url http://127.0.0.1:4566 --region ap-south-1 --output text "$@"
}

output() {
  "${TF:-terraform}" -chdir=environments/localstack output -raw "$1"
}

expect() {
  if [[ "$1" != "$2" ]]; then
    echo "Expected $2 for $3, got $1" >&2
    exit 1
  fi
  echo "OK: $3"
}

bucket=$(output documents_bucket)
cluster=$(output cluster_name)
group=$(output log_group)
repo=$(output ecr_repository_url)
expect "$(local_aws ecs describe-clusters --clusters "$cluster" --query 'clusters[0].status')" ACTIVE "ECS cluster $cluster"
expect "$(local_aws ecr describe-repositories --repository-names "${repo##*/}" --query 'repositories[0].repositoryUri')" "$repo" "ECR repository"
expect "$(local_aws logs describe-log-groups --log-group-name-prefix "$group" --query "logGroups[?logGroupName=='$group'].retentionInDays | [0]")" 7 "CloudWatch retention in days"
expect "$(local_aws s3api get-bucket-versioning --bucket "$bucket" --query Status)" Enabled "S3 versioning on $bucket"
expect "$(local_aws s3api get-bucket-encryption --bucket "$bucket" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')" AES256 "S3 default encryption"
expect "$(local_aws s3api get-public-access-block --bucket "$bucket" --query 'length(values(PublicAccessBlockConfiguration)[?@ == `true`])')" 4 "S3 public access block settings"

if worker=$(output worker_name 2>/dev/null); then
  expect "$(local_aws lambda get-function-configuration --function-name "$worker" --query State)" Active "Lambda worker $worker"
  expect "$(local_aws lambda list-event-source-mappings --function-name "$worker" --query "length(EventSourceMappings[?State=='Enabled'])")" 2 "Enabled Lambda queue mappings"
fi

if portal=$(output portal_url 2>/dev/null); then
  api=$(output api_url)
  database=$(output database_identifier)
  expect "$(local_aws rds describe-db-instances --db-instance-identifier "$database" --query 'DBInstances[0].DBInstanceStatus')" available "RDS instance $database"
  expect "$(local_aws ecs describe-services --cluster "$cluster" --services claimsense-local --query 'services[0].runningCount')" 1 "Running ECS task"
  curl -fsS --max-time 5 "$api/health" >/dev/null
  echo "OK: ECS API $api"
  expect "$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$api/claims")" 401 "Claim API requires Cognito sign-in"
  curl -fsS --max-time 5 "${portal}_stcore/health" >/dev/null
  echo "OK: ECS portal $portal"
  mapfile -t containers < <(docker ps -q --filter label=service=claimsense-local --filter label=container-index=0)
  expect "${#containers[@]}" 1 "Running API container"
  docker exec -i "${containers[0]}" python - <<'PY'
import psycopg
from claim_sense.db.session import checkpoint_dsn

with psycopg.connect(checkpoint_dsn(), connect_timeout=5) as connection:
    version, = connection.execute("SHOW server_version_num").fetchone()
    if int(version) // 10000 != 18:
        raise SystemExit(f"Expected PostgreSQL 18, got server_version_num={version}")
    print(f"OK: ECS connects to PostgreSQL {version[:2]}.{int(version[2:])}")
PY
fi
