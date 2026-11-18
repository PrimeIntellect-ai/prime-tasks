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
import json
import os
import re
import stat
import subprocess
import time

import pytest
import requests

APP_DIR = "/home/user/app"
DATA_DIR = os.path.join(APP_DIR, "data")
DEPLOY_SCRIPT = os.path.join(APP_DIR, "deploy.sh")
NGINX_CONF = os.path.join(APP_DIR, "nginx.conf")
NGINX_PID = os.path.join(APP_DIR, "nginx.pid")
SERVER_BIN = os.path.join(APP_DIR, "server")


def get_total_data_bytes(directory):
    total_size = 0
    for root, _, files in os.walk(directory):
        for name in files:
            path = os.path.join(root, name)
            if os.path.isfile(path) and not os.path.islink(path):
                total_size += os.path.getsize(path)
    return total_size


def configured_socket():
    with open(NGINX_CONF, encoding="utf-8") as f:
        config = f.read()
    matches = re.findall(r"proxy_pass\s+http://unix:([^;\s:]+):?\s*;", config)
    assert matches, "nginx.conf does not contain a Unix-socket proxy_pass target."
    assert len(set(matches)) == 1, "nginx.conf has ambiguous Unix-socket proxy targets."
    return matches[0]


def server_pids():
    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
            if argv and argv[0] and os.path.abspath(os.fsdecode(argv[0])) == SERVER_BIN:
                result.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def read_nginx_master_pid():
    try:
        with open(NGINX_PID, encoding="ascii") as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return pid
    except (FileNotFoundError, ValueError, ProcessLookupError):
        pytest.fail("Nginx is not running with the configured pid file.")


def child_pids(parent):
    children = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", encoding="ascii") as f:
                fields = f.read().split()
            if int(fields[3]) == parent:
                children.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError, IndexError):
            pass
    return children


def wait_for(predicate, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    return predicate()


def assert_status_response():
    expected_bytes = get_total_data_bytes(DATA_DIR)
    url = "http://127.0.0.1:8080/status"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to Nginx at {url}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert "data_bytes" in data, f"Key 'data_bytes' missing from JSON response: {data}"
    assert data["data_bytes"] == expected_bytes, (
        f"Expected 'data_bytes' to be {expected_bytes}, got {data['data_bytes']}."
    )


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY_SCRIPT), f"Deployment script {DEPLOY_SCRIPT} does not exist."
    mode = os.stat(DEPLOY_SCRIPT).st_mode
    assert mode & stat.S_IXUSR, f"Deployment script {DEPLOY_SCRIPT} is not executable."
    subprocess.run(["bash", "-n", DEPLOY_SCRIPT], check=True)

    with open(DEPLOY_SCRIPT, encoding="utf-8") as f:
        script = f.read()
    assert re.search(r"\bgo\s+build\b", script), "deploy.sh does not invoke go build."
    assert "-o" in script and "server" in script, (
        "deploy.sh does not direct the Go build to the server binary."
    )
    assert re.search(r"\bnginx\b", script) and re.search(r"-s\s+reload", script), (
        "deploy.sh does not request a graceful Nginx reload."
    )
    assert "-c" in script and "nginx.conf" in script, (
        "deploy.sh does not reload using the application Nginx configuration."
    )


def test_deploy_script_builds_restarts_and_reloads():
    old_server_pids = server_pids()
    assert old_server_pids, f"The Go backend daemon ({SERVER_BIN}) is not running."

    master_pid = read_nginx_master_pid()
    old_workers = child_pids(master_pid)
    assert old_workers, "Nginx has no running worker process."

    if os.path.lexists(SERVER_BIN):
        os.unlink(SERVER_BIN)

    completed = subprocess.run(
        [DEPLOY_SCRIPT],
        cwd=APP_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"deploy.sh failed: {completed.stderr}"

    assert os.path.isfile(SERVER_BIN), "deploy.sh did not create /home/user/app/server."
    assert os.access(SERVER_BIN, os.X_OK), "The rebuilt server binary is not executable."

    new_server_pids = wait_for(lambda: server_pids() - old_server_pids)
    assert new_server_pids, "deploy.sh did not start a newly built backend process."
    assert not (server_pids() & old_server_pids), (
        "deploy.sh did not terminate the previously running server instance."
    )

    assert read_nginx_master_pid() == master_pid, (
        "deploy.sh replaced Nginx instead of gracefully reloading its configuration."
    )
    reloaded_workers = wait_for(lambda: child_pids(master_pid) - old_workers)
    assert reloaded_workers, "Nginx workers were not refreshed by deploy.sh."


def test_configured_unix_socket_exists_and_is_used():
    socket_file = configured_socket()
    assert os.path.exists(socket_file), f"Configured Unix socket {socket_file} does not exist."
    mode = os.stat(socket_file).st_mode
    assert stat.S_ISSOCK(mode), f"Configured path {socket_file} is not a Unix socket."
    assert_status_response()


def test_status_endpoint_is_dynamic_and_recursive():
    probe_dir = os.path.join(DATA_DIR, ".verifier_probe", "nested")
    probe_file = os.path.join(probe_dir, "probe.bin")
    os.makedirs(probe_dir, exist_ok=True)
    try:
        with open(probe_file, "wb") as f:
            f.write(os.urandom(1733))
        assert_status_response()
    finally:
        try:
            os.unlink(probe_file)
            os.removedirs(probe_dir)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
