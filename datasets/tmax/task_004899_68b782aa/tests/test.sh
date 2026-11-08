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
import importlib.util
import os
import subprocess
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080/api/v1/deploy"
LOG_DIR = "/home/user/deploy_logs"
TOKEN = "Bearer DeployerToken-99x"


def wait_for_expected_log(path, expected, started_ns):
    for _ in range(20):
        if os.path.isfile(path):
            try:
                with open(path, "r") as f:
                    content = f.read()
                if content == expected and os.stat(path).st_mtime_ns >= started_ns:
                    return
            except OSError:
                pass
        time.sleep(0.25)

    assert os.path.isfile(path), f"Deployment log file was not created at {path}"
    assert os.path.getsize(path) > 0, f"Deployment log file {path} is empty"
    with open(path, "r") as f:
        content = f.read()
    assert content == expected, f"Unexpected deployment log content: {content!r}"
    assert os.stat(path).st_mtime_ns >= started_ns, "Deployment log was not freshly generated"


def test_status_file():
    status_file = "/home/user/status.txt"
    assert os.path.isfile(status_file), f"Status file missing: {status_file}"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "SERVICE_READY", f"Expected 'SERVICE_READY' in {status_file}, got '{content}'"


def test_log_directory_permissions():
    assert os.path.isdir(LOG_DIR), f"Deployment log directory missing: {LOG_DIR}"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "test", "-w", LOG_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"{LOG_DIR} is not writable by the runner user"


def test_scheduler_directly_executes_deployment_in_log_directory():
    scheduler_path = "/app/vendored_ci_runner-1.2.0/runner/scheduler.py"
    assert os.path.isfile(scheduler_path), f"Scheduler source missing: {scheduler_path}"

    service = "scheduler_" + uuid.uuid4().hex
    log_file = os.path.join(LOG_DIR, service + "_deployment.log")
    expected = f"Deploying {service}...\nSuccess\n"
    if os.path.exists(log_file):
        os.unlink(log_file)

    spec = importlib.util.spec_from_file_location("audited_scheduler", scheduler_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    started_ns = time.time_ns()
    module.trigger_deployment(service)
    wait_for_expected_log(log_file, expected, started_ns)


def test_webhook_authentication():
    response = requests.post(
        BASE_URL,
        headers={"Authorization": "Bearer wrong-token", "Content-Type": "application/json"},
        json={"service": "unauthorized_" + uuid.uuid4().hex, "strategy": "rolling"},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected status 401 for an invalid token, got {response.status_code}"


def test_webhook_and_deployment_log():
    service = "webhook_" + uuid.uuid4().hex
    log_file = os.path.join(LOG_DIR, service + "_deployment.log")
    expected = f"Deploying {service}...\nSuccess\n"
    if os.path.exists(log_file):
        os.unlink(log_file)

    headers = {
        "Authorization": TOKEN,
        "Content-Type": "application/json",
    }
    payload = {
        "service": service,
        "strategy": "rolling",
    }

    started_ns = time.time_ns()
    try:
        response = requests.post(BASE_URL, headers=headers, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the webhook service at {BASE_URL}: {e}")

    assert response.status_code in (200, 202), f"Expected status 200 or 202, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response was not valid JSON")
    assert data.get("status") == "deployment_started", \
        f"Expected status 'deployment_started', got {data.get('status')}"

    wait_for_expected_log(log_file, expected, started_ns)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
