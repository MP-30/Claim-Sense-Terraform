# Claim-Sense infrastructure

Claim-Sense has a FastAPI claims API, a Streamlit adjuster portal and PostgreSQL. This repository runs the application in a LocalStack ECS service and contains a separate Terraform configuration for AWS. The shared foundation provisions the ECR repository, ECS cluster, CloudWatch log group and private, versioned S3 bucket.

## Run Claim-Sense in LocalStack ECS

Use Docker, the authenticated LocalStack CLI (`localstack`), Terraform 1.5 or newer, the AWS CLI, curl and Make. The local environment uses test credentials, region `ap-south-1`, and a gateway at `127.0.0.1:4566`. Its Terraform state lives under `environments/localstack/`. From a fresh checkout, build the application image from the sibling repository:

```bash
docker build -t claim-sense-api:latest ~/PycharmProjects/Claim-Sense
```

```bash
cd ~/PycharmProjects/Claim-Sense-Terraform
make local-up
make local-init
make local-apply   # Create the foundation on the first run.
make local-image   # Push the existing Docker image and record its tag.
make local-apply   # Deploy the ECS service using that tag.
make local-check
make local-seed    # Populate the ECS database and generate 20 sample claims.
```

Open [the ECS portal](http://127.0.0.1:18501/) or [the ECS API docs](http://127.0.0.1:18000/docs). On a fresh environment, the first apply adds seven resources. The second adds the task definition, service and execution permissions. Run `make local-plan` again to check for drift. Run `terraform -chdir=environments/localstack output` for the ports, registry URL and bucket name.

The local task runs the API, portal and PostgreSQL 18. Database and PDF files live in separate directories under `~/.cache/claimsense-ecs` and survive task replacement. The API reads and writes PDFs on its host-mounted data directory. S3 integration is a later step.

The portal and database can start without a model key. For claim processing, create the LocalStack SSM `SecureString` at `/claimsense/openai_api_key` and put the parameter name in the ignored `environments/localstack/local-model.auto.tfvars.json` file. Use `openai_model` to select the same model as the backend `.env`.

```json
{
  "openai_parameter_name": "/claimsense/openai_api_key",
  "openai_model": "gpt-5.4-nano"
}
```

Run `make local-apply` so the replacement task receives the key from SSM. If a claim failed with `OpenAIError: Missing credentials`, submit it again after the new task starts.

`local-up` starts LocalStack with the direct ECR endpoint and a Docker network that publishes task ports on loopback. It reuses a running gateway. If your existing emulator uses different settings, stop it and start it with `make local-up`. Keep `~/.cache/claimsense-localstack`, the ECS data directory and the local Terraform state across restarts.

## Teardown

Run `make local-destroy` while LocalStack is running and confirm its plan. An S3 bucket containing PDFs must be emptied, including all versions and delete markers, before it can be destroyed. The demo ECR repository allows deletion with images. If this project started the emulator, run `localstack stop` after teardown.

## Application deployment

The repository root is the **AWS** deployment configuration. It uses the same foundation module and also defines IAM, network access, an ECS task definition and a Fargate service. The `local-*` targets use the emulator configuration.

The next stage is persistent PostgreSQL and its connection secret. After that, wire the API's filesystem-based PDF uploads to S3, publish the image to ECR, inject the runtime secrets and start the API and portal. The deployment test is to submit a synthetic claim, replace the API task, and approve the saved review with its documents still available.
