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
import glob
import os
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

PORT = 8085
PROFILE_ENV = None
SERVICE_PIDS = set()


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc_path in glob.glob("/proc/[0-9]*"):
        pid = int(proc_path.rsplit("/", 1)[1])
        for fd in glob.glob(proc_path + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def stop_port_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(port), f"Could not clear existing listener on port {port}"


def exported_profile_environment():
    fd, output_path = tempfile.mkstemp(prefix="profile-env-")
    os.close(fd)
    try:
        with open(output_path, "wb") as output:
            result = subprocess.run(
                ["bash", "--noprofile", "--norc", "-c", "source /home/user/.bash_profile; env"],
                stdout=output,
                stderr=subprocess.DEVNULL,
                timeout=10,
                env={**os.environ, "HOME": "/home/user"},
            )
        assert result.returncode == 0, ".bash_profile could not be sourced successfully"
        with open(output_path, "r", errors="replace") as f:
            return dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
    finally:
        try:
            os.unlink(output_path)
        except FileNotFoundError:
            pass


@pytest.fixture(scope="session", autouse=True)
def launch_submitted_deployment():
    global PROFILE_ENV, SERVICE_PIDS

    PROFILE_ENV = exported_profile_environment()
    assert PROFILE_ENV.get("DEPLOY_ENVIRONMENT") == "production", (
        "DEPLOY_ENVIRONMENT is not exported as production by .bash_profile"
    )

    script = "/home/user/start_daemon.sh"
    assert os.path.isfile(script), f"Missing {script}"
    assert os.access(script, os.X_OK), f"{script} is not executable"

    # Remove any pre-existing or substitute listener, then require the submitted
    # startup script to create a fresh service.
    stop_port_listeners(PORT)
    env = os.environ.copy()
    env.update({"HOME": "/home/user", "DEPLOY_ENVIRONMENT": PROFILE_ENV["DEPLOY_ENVIRONMENT"]})
    result = subprocess.run(
        [script],
        cwd="/home/user",
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
    )
    assert result.returncode == 0, f"{script} exited with status {result.returncode}"

    deadline = time.time() + 8
    while time.time() < deadline:
        SERVICE_PIDS = listener_pids(PORT)
        if SERVICE_PIDS:
            break
        time.sleep(0.2)
    assert SERVICE_PIDS, f"{script} did not start a listener on port {PORT}"

    cmdlines = []
    for pid in SERVICE_PIDS:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except FileNotFoundError:
            continue
        cmdlines.append(args)
    assert any("/home/user/server.py" in args for args in cmdlines), (
        "The listener created by start_daemon.sh is not running /home/user/server.py"
    )


def test_bash_profile_env_var():
    path = "/home/user/.bash_profile"
    assert os.path.exists(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read()

    has_env = (
        "DEPLOY_ENVIRONMENT=production" in content or
        "DEPLOY_ENVIRONMENT='production'" in content or
        'DEPLOY_ENVIRONMENT="production"' in content
    )
    assert has_env, "DEPLOY_ENVIRONMENT=production is not set in .bash_profile"
    assert PROFILE_ENV.get("DEPLOY_ENVIRONMENT") == "production", (
        "DEPLOY_ENVIRONMENT must be exported, not merely assigned"
    )


def test_deploy_data_disk_space():
    path = "/home/user/deploy_data"
    assert os.path.exists(path), f"Missing {path}"
    total, used, free = shutil.disk_usage(path)
    assert free > 0, f"Disk space at {path} is still completely full. Free space: {free} bytes."
    obsolete = glob.glob("/home/user/deploy_data/logs/old_log_*.txt")
    assert not obsolete, f"Obsolete deployment logs were not deleted: {obsolete}"


def test_service_unauthorized():
    url = f"http://127.0.0.1:{PORT}/version"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}. Is it running? Error: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"


@pytest.mark.parametrize("authorization", [
    "Bearer wrong",
    "Bearer secret99-extra",
    "Basic secret99",
    "bearer secret99",
])
def test_service_rejects_incorrect_authorization(authorization):
    url = f"http://127.0.0.1:{PORT}/version"
    response = requests.get(url, headers={"Authorization": authorization}, timeout=5)
    assert response.status_code == 401, (
        f"Expected 401 for invalid Authorization header {authorization!r}, got {response.status_code}"
    )


def test_service_rejects_random_token():
    url = f"http://127.0.0.1:{PORT}/version"
    token = uuid.uuid4().hex
    response = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=5)
    assert response.status_code == 401, f"Expected 401 for a random invalid token, got {response.status_code}"


def test_service_authorized():
    url = f"http://127.0.0.1:{PORT}/version"
    headers = {"Authorization": "Bearer secret99"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}. Error: {e}")

    assert response.status_code == 200, (
        f"Expected 200 OK with correct token, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert data.get("version") == "v2", f"Expected version 'v2', got {data.get('version')}"
    assert listener_pids(PORT), "Service stopped running during verification"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
