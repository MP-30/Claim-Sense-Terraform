TF ?= terraform
LOCAL_TF = $(TF) -chdir=environments/localstack
GATEWAY = http://127.0.0.1:4566

.PHONY: local-up local-init local-plan local-apply local-check local-destroy

local-up:
	@if curl -fsS --max-time 3 $(GATEWAY)/_localstack/health >/dev/null 2>&1; then \
		echo "Using LocalStack at $(GATEWAY)"; \
	else \
		LOCALSTACK_VOLUME_DIR="$(HOME)/.cache/claimsense-localstack" LOCALSTACK_PERSISTENCE=1 localstack start --detached --stack localstack; \
	fi
	@curl --retry 30 --retry-connrefused --retry-delay 1 --max-time 3 -fsS $(GATEWAY)/_localstack/health >/dev/null

local-init:
	$(LOCAL_TF) init
	$(LOCAL_TF) validate

local-plan:
	$(LOCAL_TF) plan

local-apply:
	$(LOCAL_TF) apply

local-check:
	@TF="$(TF)" bash scripts/check-local.sh

local-destroy:
	$(LOCAL_TF) destroy
