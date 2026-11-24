"""Start a Claim-Sense container on LocalStack's Docker network."""

import ipaddress
import os
from pathlib import Path
import socket
import sys
import time
from urllib.request import urlopen


ADDRESSES = Path("/run/claimsense")


def wait_for_peer(name, probe):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        try:
            address = str(ipaddress.IPv4Address((ADDRESSES / name).read_text().strip()))
            with probe(address):
                return address
        except (OSError, ValueError):
            time.sleep(1)
    raise RuntimeError(f"Timed out waiting for the ECS {name} container")


def main():
    container, api_port, ui_port = sys.argv[1:]
    if container == "api":
        # An older task revision can still use the original database container.
        if "POSTGRES_HOST" not in os.environ:
            os.environ["POSTGRES_HOST"] = wait_for_peer(
                "db", lambda address: socket.create_connection((address, 5432), timeout=2)
            )
        address_file = ADDRESSES / "api.tmp"
        address_file.write_text(socket.gethostbyname(socket.gethostname()))
        address_file.replace(ADDRESSES / "api")
        command = ["uvicorn", "claim_sense.main:app", "--host", "0.0.0.0", "--port", api_port]
    else:
        api_address = wait_for_peer(
            "api", lambda address: urlopen(f"http://{address}:{api_port}/health", timeout=2)
        )
        os.environ["API_URL"] = f"http://{api_address}:{api_port}"
        command = [
            "streamlit", "run", "ui/portal.py", "--server.port", ui_port,
            "--server.address", "0.0.0.0", "--server.headless", "true", "--client.toolbarMode", "viewer",
        ]
    os.execvp(command[0], command)


if __name__ == "__main__":
    main()
