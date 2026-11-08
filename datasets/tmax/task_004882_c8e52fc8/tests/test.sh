#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
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
import ast
import json
import os
import secrets
import subprocess
import time

import pytest
import requests


@pytest.fixture(scope="module", autouse=True)
def start_api_service():
    """Run the user's startup script and wait for the API to become available."""
    script_path = "/home/user/start_services.sh"
    assert os.path.isfile(script_path), f"Startup script {script_path} not found."

    subprocess.run(["bash", script_path], check=True)

    service_up = False
    for _ in range(20):
        try:
            requests.get("http://127.0.0.1:5000/api/v1/data", timeout=1)
            service_up = True
            break
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)

    assert service_up, "API Gateway did not start on 127.0.0.1:5000 within the timeout."

    yield

    pid_file = "/home/user/api.pid"
    if os.path.isfile(pid_file):
        try:
            with open(pid_file, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 9)
        except (ValueError, ProcessLookupError, OSError):
            pass


def test_data_mount_config():
    """Verify the storage setup and config.json content."""
    config_path = "/home/user/data_mount/config.json"
    assert os.path.isfile(config_path), f"Config file {config_path} does not exist."

    with open(config_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {config_path} does not contain valid JSON.")

    expected_data = {"status": "migrated", "version": "1.0"}
    assert data == expected_data, f"Config JSON content mismatch. Expected {expected_data}, got {data}"


def test_adapter_exists():
    """Verify the adapter module exists."""
    assert os.path.isfile("/app/adapter.py"), "Adapter script /app/adapter.py does not exist."


def test_adapter_uses_pexpect_spawn():
    """Verify that the adapter actually invokes the legacy process through pexpect."""
    with open("/app/adapter.py", "r") as f:
        tree = ast.parse(f.read(), filename="/app/adapter.py")

    pexpect_aliases = set()
    spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    pexpect_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or "spawn")

    assert pexpect_aliases or spawn_aliases, "/app/adapter.py must import pexpect."

    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in spawn_aliases:
            uses_spawn = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "spawn"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in pexpect_aliases
        ):
            uses_spawn = True

    assert uses_spawn, "/app/adapter.py must call pexpect.spawn to run the legacy CLI."


def test_api_imports_and_calls_adapter():
    """Verify that the gateway imports and calls code from the adapter module."""
    with open("/app/api_gateway.py", "r") as f:
        tree = ast.parse(f.read(), filename="/app/api_gateway.py")

    module_aliases = set()
    symbol_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "adapter":
                    module_aliases.add(alias.asname or "adapter")
        elif isinstance(node, ast.ImportFrom) and node.module == "adapter":
            for alias in node.names:
                symbol_aliases.add(alias.asname or alias.name)

    assert module_aliases or symbol_aliases, "/app/api_gateway.py must import the adapter."

    calls_adapter = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in symbol_aliases:
            calls_adapter = True
        elif (
            isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in module_aliases
        ):
            calls_adapter = True

    assert calls_adapter, "/app/api_gateway.py must call the imported adapter."


def test_api_auth_failure():
    """Verify that the API returns 401 Unauthorized when the token is missing or incorrect."""
    url = "http://127.0.0.1:5000/api/v1/data"

    response = requests.get(url)
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"

    headers = {"Authorization": "Bearer wrong-token"}
    response = requests.get(url, headers=headers)
    assert response.status_code == 401, f"Expected 401 for incorrect auth, got {response.status_code}"


def test_api_success():
    """Verify that the API returns 200 OK and the correct data when authenticated."""
    url = "http://127.0.0.1:5000/api/v1/data"
    headers = {"Authorization": "Bearer migrate-token-99"}

    response = requests.get(url, headers=headers)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        response_data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"API response is not valid JSON. Response text: {response.text}")

    expected_response = {
        "source": "legacy",
        "data": {"status": "migrated", "version": "1.0"},
    }
    assert response_data == expected_response, f"API response data mismatch. Expected {expected_response}, got {response_data}"


def test_api_really_drives_legacy_cli():
    """Replace the CLI with a compatible probe and require a fresh, derived response."""
    legacy_path = "/app/legacy_cli.py"
    with open(legacy_path, "rb") as f:
        original = f.read()
    original_mode = os.stat(legacy_path).st_mode

    nonce = secrets.token_hex(12)
    payload = {"status": "probe-" + nonce, "version": nonce}
    trace_path = "/tmp/legacy_probe_" + nonce + ".json"
    probe = f'''#!/usr/bin/env python3
import json
import sys

trace_path = {trace_path!r}
payload = {payload!r}
print("Welcome to Legacy Data System")
try:
    username = input("Username: ")
    password = input("Password: ")
    if username != "admin" or password != "supersecret":
        print("Access Denied")
        sys.exit(1)
    print("Access Granted")
    while True:
        command = input("Command: ")
        with open(trace_path, "w") as trace:
            json.dump({{"username": username, "password": password, "command": command}}, trace)
        if command == "QUERY /home/user/data_mount/config.json":
            print(json.dumps(payload))
        elif command == "EXIT":
            break
        else:
            print("Unknown command")
except EOFError:
    pass
'''

    try:
        with open(legacy_path, "w") as f:
            f.write(probe)
        os.chmod(legacy_path, 0o755)

        response = requests.get(
            "http://127.0.0.1:5000/api/v1/data",
            headers={"Authorization": "Bearer migrate-token-99"},
            timeout=10,
        )
        assert response.status_code == 200, f"Probe request returned {response.status_code}: {response.text}"
        assert response.json() == {"source": "legacy", "data": payload}, (
            "The API did not return the fresh value emitted by the legacy CLI; "
            "a fixed or directly-read response is not acceptable."
        )
        assert os.path.isfile(trace_path), "The legacy CLI probe was not invoked."
        with open(trace_path, "r") as f:
            trace = json.load(f)
        assert trace == {
            "username": "admin",
            "password": "supersecret",
            "command": "QUERY /home/user/data_mount/config.json",
        }, f"Incorrect legacy CLI interaction: {trace}"
    finally:
        with open(legacy_path, "wb") as f:
            f.write(original)
        os.chmod(legacy_path, original_mode)
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
