TF ?= terraform
LOCAL_TF = $(TF) -chdir=environments/localstack
GATEWAY = http://127.0.0.1:4566
LOCAL_NETWORK = claimsense-local
APP_DIR ?= $(abspath ../Claim-Sense)
APP_IMAGE ?= claim-sense-api:latest

.PHONY: local-up local-init local-image local-plan local-apply local-check local-seed local-user local-destroy

local-up:
	@if curl -fsS --max-time 3 $(GATEWAY)/_localstack/health >/dev/null 2>&1; then \
		echo "Using LocalStack at $(GATEWAY)"; \
	else \
		(docker network inspect $(LOCAL_NETWORK) >/dev/null 2>&1 || \
			docker network create --opt com.docker.network.bridge.host_binding_ipv4=127.0.0.1 $(LOCAL_NETWORK)) && \
		LOCALSTACK_VOLUME_DIR="$(HOME)/.cache/claimsense-localstack" LOCALSTACK_PERSISTENCE=1 LOCALSTACK_ECR_ENDPOINT_STRATEGY=off LOCALSTACK_ECS_PERSIST_CLUSTER_CONTENTS=1 localstack start --detached --stack localstack --network $(LOCAL_NETWORK); \
	fi
	@curl --retry 30 --retry-all-errors --retry-delay 1 --max-time 3 -fsS $(GATEWAY)/_localstack/health >/dev/null

local-init:
	$(LOCAL_TF) init
	$(LOCAL_TF) validate

local-image:
	@TF="$(TF)" bash scripts/publish-local-image.sh "$(APP_DIR)" "$(APP_IMAGE)"

local-plan:
	$(LOCAL_TF) plan

local-apply:
	$(LOCAL_TF) apply

local-check:
	@TF="$(TF)" bash scripts/check-local.sh

local-user:
	@TF="$(TF)" python3 scripts/create-local-user.py "$(USERNAME)"

local-seed:
	@set -- $$(docker ps -q --filter label=service=claimsense-local --filter label=container-index=0); \
	test "$$#" -eq 1 || { echo "Expected one running Claim-Sense API container." >&2; exit 1; }; \
	docker exec -i "$$1" python - < "$(APP_DIR)/scripts/generate_data.py"

local-destroy:
	$(LOCAL_TF) destroy
