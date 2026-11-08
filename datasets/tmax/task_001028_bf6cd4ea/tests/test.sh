#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "yaml:pyyaml"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import json
import pytest
import yaml


def test_proxy_package_fixed_and_installed():
    """Test that cloud-proxy is editable-installed and handles POST normally."""
    result = subprocess.run(["pip", "list", "--format=json"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run pip list"
    packages = json.loads(result.stdout)
    installed = any(pkg.get("name") == "cloud-proxy" for pkg in packages)
    assert installed, "cloud-proxy package is not installed."

    server_file = "/app/cloud-proxy-0.1.0/cloud_proxy/server.py"
    assert os.path.isfile(server_file), f"{server_file} is missing."
    with open(server_file, "r") as f:
        content = f.read()

    assert 'status=403' not in content or 'POST forbidden' not in content, \
        "The POST perturbation is still present in server.py."

    probe = r'''
import asyncio
import os
import cloud_proxy
from cloud_proxy import server
from aiohttp.test_utils import TestClient, TestServer

package_file = os.path.realpath(cloud_proxy.__file__)
assert package_file.startswith('/app/cloud-proxy-0.1.0/cloud_proxy/'), package_file

async def main():
    client = TestClient(TestServer(server.app))
    await client.start_server()
    try:
        get_response = await client.get('/verification')
        assert get_response.status == 200, get_response.status
        assert await get_response.text() == 'OK'

        post_response = await client.post('/verification', data=b'probe')
        assert post_response.status == 200, post_response.status
        assert await post_response.text() == 'OK'
    finally:
        await client.close()

asyncio.run(main())
'''
    result = subprocess.run(["python3", "-c", probe], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"Installed proxy failed its HTTP behavior test:\n{result.stderr}"


def test_fstab_configuration():
    """Test that the fstab configuration is one complete, valid entry."""
    fstab_path = "/home/user/migration_fstab.txt"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    parts = content.split()
    assert len(parts) >= 4, f"fstab entry seems incomplete: {content}"
    assert parts[0] == "10.0.0.5:/var/nfs/legacy", f"Incorrect file system: {parts[0]}"
    assert parts[1] == "/mnt/legacy_assets", f"Incorrect mount point: {parts[1]}"
    assert parts[2] == "nfs4", f"Incorrect file system type: {parts[2]}"

    options = parts[3].split(",")
    expected_options = ["ro", "nosuid", "nodev", "noexec", "bg", "soft", "rsize=8192", "wsize=8192"]
    for opt in expected_options:
        assert opt in options, f"Missing option '{opt}' in fstab entry."

    entries = [line.strip() for line in content.splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    assert len(entries) == 1, "migration_fstab.txt must contain exactly one fstab entry"
    entry_parts = entries[0].split()
    assert len(entry_parts) == 6, "The fstab entry must contain all six fields"
    assert sorted(entry_parts[3].split(",")) == sorted(expected_options), \
        "The fstab option list contains missing, duplicate, or unexpected options"
    assert entry_parts[4].isdigit() and entry_parts[5].isdigit(), \
        "The dump and pass fields must be numeric"


def _publishes_8080(service):
    expose = service.get("expose", [])
    if not isinstance(expose, list):
        return False
    for item in expose:
        if str(item).split("/", 1)[0] == "8080":
            return True

    ports = service.get("ports", [])
    if not isinstance(ports, list):
        return False
    for item in ports:
        if isinstance(item, dict):
            if str(item.get("target", "")) == "8080":
                return True
        else:
            value = str(item).split("/", 1)[0]
            if value.split(":")[-1] == "8080":
                return True
    return False


def test_docker_compose_configuration():
    """Test that docker-compose.yml is valid YAML with the requested service."""
    compose_path = "/home/user/docker-compose.yml"
    assert os.path.isfile(compose_path), f"File {compose_path} does not exist."

    with open(compose_path, "r") as f:
        content = f.read()

    assert "cloud-proxy:" in content or "cloud-proxy" in content, \
        "Service 'cloud-proxy' not defined in docker-compose.yml"
    assert "python:3.9-slim" in content, "Image 'python:3.9-slim' not specified in docker-compose.yml"
    assert "8080" in content, "Port 8080 not exposed in docker-compose.yml"
    assert "/home/user/migrator_router.py:/usr/local/bin/router.py" in content.replace(" ", ""), \
        "Volume mount for router.py is incorrect or missing."

    document = yaml.safe_load(content)
    assert isinstance(document, dict), "docker-compose.yml must contain a YAML mapping"
    services = document.get("services")
    assert isinstance(services, dict), "docker-compose.yml must define a services mapping"
    service = services.get("cloud-proxy")
    assert isinstance(service, dict), "Service 'cloud-proxy' must be a service mapping"
    assert service.get("image") == "python:3.9-slim", "cloud-proxy has the wrong image"
    assert _publishes_8080(service), "cloud-proxy does not expose or publish container port 8080"

    volumes = service.get("volumes", [])
    assert isinstance(volumes, list), "cloud-proxy volumes must be a list"
    valid_mount = False
    for volume in volumes:
        if isinstance(volume, str):
            fields = volume.split(":")
            valid_mount |= len(fields) >= 2 and fields[0] == "/home/user/migrator_router.py" and fields[1] == "/usr/local/bin/router.py"
        elif isinstance(volume, dict):
            valid_mount |= volume.get("source") == "/home/user/migrator_router.py" and volume.get("target") == "/usr/local/bin/router.py"
    assert valid_mount, "The router script is not mounted at the required container path"


def test_routing_logic_fuzz_equivalence():
    """Execute the submitted router and compare it with the isolated oracle."""
    agent_script = "/home/user/migrator_router.py"
    oracle_script = "/tests/migrator_router.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."
    assert open(agent_script, "rb").read() != open(oracle_script, "rb").read(), \
        "Submitted router must not be a byte-identical copy of the reference implementation"

    random.seed(42)
    charset = string.ascii_letters + string.digits + "/.?=&_-"
    seeds = ["/static/", ".php", "/api/v1/", "/api/v2/"]

    inputs = [
        "/static/css/main.css",
        "/static/file?x=1?y=2",
        "/login.php?z=1&a=2",
        "/index.php?empty=&a=2&a=1",
        "/api/v1/users?active=true",
        "/api/v2/items?x=1",
        "/ordinary/path?x=1",
        "/api/v1/test.php?z=9&a=1",
    ]

    for _ in range(500):
        length = random.randint(5, 150)
        base = "".join(random.choices(charset, k=length))
        if random.random() < 0.5:
            seed = random.choice(seeds)
            pos = random.randint(0, len(base))
            base = base[:pos] + seed + base[pos:]
        inputs.append(base)

    for uri in inputs:
        oracle_res = subprocess.run(
            ["python3", oracle_script, uri], capture_output=True, text=True, timeout=10
        )
        agent_res = subprocess.run(
            ["python3", agent_script, uri], capture_output=True, text=True, timeout=10
        )

        assert oracle_res.returncode == 0, f"Oracle failed on input: {uri}\n{oracle_res.stderr}"
        assert agent_res.returncode == 0, f"Agent script failed on input: {uri}\nError: {agent_res.stderr}"
        assert oracle_res.stdout.strip() == agent_res.stdout.strip(), (
            f"Mismatch on input: {uri}\n"
            f"Expected (Oracle): {oracle_res.stdout.strip()}\n"
            f"Got (Agent):       {agent_res.stdout.strip()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
