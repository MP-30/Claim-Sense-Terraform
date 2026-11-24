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
