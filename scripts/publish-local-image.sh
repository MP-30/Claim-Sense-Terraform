#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_dir=$1
image=$2
repo=$("${TF:-terraform}" -chdir=environments/localstack output -raw ecr_repository_url)
case "$repo" in
  localhost.localstack.cloud:*/claimsense) ;;
  *)
    echo "Start LocalStack with ECR_ENDPOINT_STRATEGY=off and run make local-apply to refresh the registry URL." >&2
    exit 1
    ;;
esac

data_dir="$HOME/.cache/claimsense-ecs/data"
mkdir -p "$data_dir" "$HOME/.cache/claimsense-ecs/postgres" "$HOME/.cache/claimsense-ecs/run"
install -m 644 "$app_dir/data/policy_wording.md" "$data_dir/policy_wording.md"

image_id=$(docker image inspect "$image" --format '{{.Id}}')
tag="dev-${image_id#sha256:}"
docker tag "$image" "$repo:$tag"
docker push "$repo:$tag"
printf 'image_tag = "%s"\n' "$tag" > environments/localstack/local-deployment.auto.tfvars
