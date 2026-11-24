# Claim-Sense infrastructure

Claim-Sense has a FastAPI claims API, a Streamlit adjuster portal and PostgreSQL. This repository provides a LocalStack environment for building out its AWS infrastructure. The first stage provisions an ECR repository for the application image, an empty ECS cluster, a CloudWatch log group with seven-day retention, and a private, versioned S3 bucket with AES-256 default encryption for claim PDFs.

## Run the first stage locally

Use Docker, the authenticated LocalStack CLI (`localstack`), Terraform 1.5 or newer, the AWS CLI, curl and Make. The local environment uses test credentials, region `ap-south-1`, and a gateway at `127.0.0.1:4566`. Its Terraform state lives under `environments/localstack/`. The sibling application's Compose stack can keep running.

```bash
cd ~/PycharmProjects/Claim-Sense-Terraform
make local-up
make local-init
make local-plan
make local-apply
make local-check
```

On a fresh environment the plan adds seven resources. Review the plan and enter `yes` at the apply prompt. The check queries the running gateway for the cluster, registry, log retention and bucket protections. Run `make local-plan` again to check for drift. To see the bucket name and registry URL, run `terraform -chdir=environments/localstack output`.

`local-up` reuses a running gateway. When it starts one, it enables persistence and stores emulator data in `~/.cache/claimsense-localstack`. Keep this directory and the local Terraform state across restarts.

## Teardown

Run `make local-destroy` while LocalStack is running and confirm its plan. An S3 bucket containing PDFs must be emptied, including all versions and delete markers, before it can be destroyed. The demo ECR repository allows deletion with images. If this project started the emulator, run `localstack stop` after teardown.

## Application deployment

The repository root is the **AWS** deployment configuration. It uses the same foundation module and also defines IAM, network access, an ECS task definition and a Fargate service. Run the `local-*` targets above for the emulator. The local stage launches zero application tasks.

The next stage is persistent PostgreSQL and its connection secret. After that, wire the API's filesystem-based PDF uploads to S3, publish the image to ECR, inject the runtime secrets and start the API and portal. The deployment test is to submit a synthetic claim, replace the API task, and approve the saved review with its documents still available.
