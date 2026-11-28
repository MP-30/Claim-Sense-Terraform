#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_dir=$1
image=$2
kind=${3:-app}
repo=$("${TF:-terraform}" -chdir=environments/localstack output -raw ecr_repository_url)
case "$repo" in
  localhost.localstack.cloud:*/claimsense) ;;
  *)
    echo "Start LocalStack with ECR_ENDPOINT_STRATEGY=off and run make local-apply to refresh the registry URL." >&2
    exit 1
    ;;
esac

image_id=$(docker image inspect "$image" --format '{{.Id}}')
if [[ "$kind" == worker ]]; then
  tag="worker-${image_id#sha256:}"
  tag_variable=worker_image_tag
  tfvars=environments/localstack/local-worker.auto.tfvars
else
  data_dir="$HOME/.cache/claimsense-ecs/data"
  mkdir -p "$data_dir" "$HOME/.cache/claimsense-ecs/run"
  install -m 644 "$app_dir/data/policy_wording.md" "$data_dir/policy_wording.md"
  tag="dev-${image_id#sha256:}"
  tag_variable=image_tag
  tfvars=environments/localstack/local-deployment.auto.tfvars
fi
docker tag "$image" "$repo:$tag"
docker push "$repo:$tag"
printf '%s = "%s"\n' "$tag_variable" "$tag" > "$tfvars"
