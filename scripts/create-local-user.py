"""Provision a LocalStack Cognito user without storing credentials in Terraform."""

import argparse
from getpass import getpass
import json
import os
from pathlib import Path
import secrets
import subprocess
from tempfile import NamedTemporaryFile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("username")
    parser.add_argument("--generate", type=Path, metavar="PRIVATE_FILE")
    args = parser.parse_args()
    if len(args.username) < 2:
        parser.error("Enter a username of at least two characters.")
    if args.generate and args.generate.exists():
        parser.error("Choose a new credentials file.")

    if args.generate:
        password = f"Aa9!{secrets.token_urlsafe(24)}"
    else:
        password = getpass("Cognito password: ")
        if password != getpass("Confirm password: "):
            parser.error("Passwords must match.")
    if (len(password) < 12 or not any(c.islower() for c in password)
            or not any(c.isupper() for c in password) or not any(c.isdigit() for c in password)
            or not any(not c.isalnum() and not c.isspace() for c in password)):
        parser.error("Use at least 12 characters, including upper and lowercase letters, a number and a symbol.")

    root = Path(__file__).resolve().parents[1]
    pool = subprocess.check_output(
        [os.getenv("TF", "terraform"), "-chdir=environments/localstack", "output", "-raw", "cognito_user_pool_id"],
        cwd=root, text=True,
    ).strip()
    aws_env = dict(os.environ, AWS_ACCESS_KEY_ID="test", AWS_SECRET_ACCESS_KEY="test",
                   AWS_EC2_METADATA_DISABLED="true", AWS_PAGER="")
    for key in ("AWS_SESSION_TOKEN", "AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
        aws_env.pop(key, None)
    aws = ["aws", "--endpoint-url", "http://127.0.0.1:4566", "--region", "ap-south-1", "cognito-idp"]
    subprocess.run(
        [*aws, "admin-create-user", "--user-pool-id", pool, "--username", args.username,
         "--message-action", "SUPPRESS"],
        env=aws_env, stdout=subprocess.DEVNULL, check=True,
    )
    with NamedTemporaryFile(mode="w") as payload:
        json.dump({"UserPoolId": pool, "Username": args.username, "Password": password, "Permanent": True}, payload)
        payload.flush()
        result = subprocess.run(
            [*aws, "admin-set-user-password", "--cli-input-json", f"file://{payload.name}"],
            env=aws_env, capture_output=True, text=True,
        )
    if result.returncode:
        raise SystemExit(result.stderr.replace(password, "[redacted]"))
    if args.generate:
        fd = os.open(args.generate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as credentials:
            credentials.write(f"Username: {args.username}\nPassword: {password}\n")
        print(f"Credentials saved to {args.generate}")
    else:
        print(f"Cognito user {args.username} is ready.")


if __name__ == "__main__":
    main()
