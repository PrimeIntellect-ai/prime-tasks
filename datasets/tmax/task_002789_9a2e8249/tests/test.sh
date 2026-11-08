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
import os
import re
import signal
import subprocess
import tempfile
import time

import pytest
import requests
from requests.auth import HTTPBasicAuth

PORT = 8081
USER = "netadmin"
PASS = "pWd99xyz"
LOG_FILE = "/home/user/app_logs/service.log"
LOGROTATE_CONF = "/home/user/logrotate.conf"
SERVICE_SOURCE = "/home/user/service.go"
START_SCRIPT = "/home/user/start.sh"
BASE_URL = f"http://127.0.0.1:{PORT}"
BUILD_PATH = "/tmp/verifier-service-binary"
RUN_CWD = "/tmp/verifier-service-cwd"


def listener_pids(port):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local = fields[1]
            state = fields[3]
            if local.rsplit(":", 1)[-1].upper() == wanted_port and state == "0A":
                inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(int(entry))
                break
    return pids


def stop_existing_service():
    pids = listener_pids(PORT)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_pids(PORT):
        time.sleep(0.1)
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(PORT):
        time.sleep(0.1)
    assert not listener_pids(PORT), f"Could not clear port {PORT} before testing start.sh"


def wait_for_service():
    deadline = time.time() + 25
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(
                f"{BASE_URL}/ping",
                auth=HTTPBasicAuth(USER, PASS),
                timeout=1,
            )
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    pytest.fail(f"Service did not start on port {PORT}; last error: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def build_and_start_actual_go_service():
    assert os.path.isfile(SERVICE_SOURCE), f"Go source {SERVICE_SOURCE} does not exist"
    assert os.path.isfile(START_SCRIPT), f"Startup script {START_SCRIPT} does not exist"
    assert os.access(START_SCRIPT, os.X_OK), f"Startup script {START_SCRIPT} is not executable"

    build = subprocess.run(
        ["go", "build", "-o", BUILD_PATH, SERVICE_SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"service.go does not compile:\n{build.stderr}"
    assert os.path.isfile(BUILD_PATH) and os.access(BUILD_PATH, os.X_OK)

    stop_existing_service()
    os.makedirs(RUN_CWD, exist_ok=True)
    os.chmod(RUN_CWD, 0o777)
    try:
        os.remove(LOG_FILE)
    except FileNotFoundError:
        pass

    started = subprocess.run(
        ["runuser", "-u", "user", "--", START_SCRIPT],
        cwd=RUN_CWD,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
    assert started.returncode == 0, f"start.sh exited with status {started.returncode}"
    wait_for_service()

    pids = listener_pids(PORT)
    assert pids, f"No process is listening on port {PORT}"
    go_processes = []
    diagnostics = []
    for pid in pids:
        result = subprocess.run(
            ["go", "version", "-m", f"/proc/{pid}/exe"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        diagnostics.append(f"pid {pid}: {result.stdout}{result.stderr}")
        if result.returncode == 0 and re.search(r"\bgo1\d+(?:\.\d+)*\b", result.stdout):
            go_processes.append(pid)
    assert go_processes, "The process serving port 8081 is not a compiled Go program. " + " | ".join(diagnostics)

    yield


def test_service_ping_authorized():
    try:
        response = requests.get(f"{BASE_URL}/ping", auth=HTTPBasicAuth(USER, PASS), timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service on port {PORT}: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "pong", f"Expected response body 'pong', got '{response.text}'"


def test_service_ping_unauthorized():
    try:
        response_no_auth = requests.get(f"{BASE_URL}/ping", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service on port {PORT}: {e}")
    assert response_no_auth.status_code == 401, f"Expected status 401 for missing auth, got {response_no_auth.status_code}"

    try:
        response_bad_auth = requests.get(f"{BASE_URL}/ping", auth=HTTPBasicAuth(USER, "wrongpass"), timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service on port {PORT}: {e}")
    assert response_bad_auth.status_code == 401, f"Expected status 401 for bad auth, got {response_bad_auth.status_code}"


def test_log_file_created_and_go_log_uses_absolute_path():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    before = os.path.getsize(LOG_FILE)

    relative_log = os.path.join(RUN_CWD, "service.log")
    try:
        os.remove(relative_log)
    except FileNotFoundError:
        pass

    # A second instance must fail to bind. Its Go log output must still be
    # appended to the required absolute file even from a different cwd.
    duplicate = subprocess.run(
        ["runuser", "-u", "user", "--", BUILD_PATH],
        cwd=RUN_CWD,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert duplicate.returncode != 0, "A duplicate service unexpectedly remained running on the occupied port"
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} disappeared"
    after = os.path.getsize(LOG_FILE)
    assert after > before, "Running the compiled Go service did not append Go log output to the required log file"
    assert not os.path.exists(relative_log), f"Service wrote a cwd-relative log at {relative_log}"


def test_logrotate_config():
    assert os.path.isfile(LOGROTATE_CONF), f"logrotate configuration {LOGROTATE_CONF} does not exist."
    with open(LOGROTATE_CONF, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert LOG_FILE in content, f"Log file path {LOG_FILE} not found in {LOGROTATE_CONF}"
    assert re.search(r"\bdaily\b", content), f"'daily' directive missing in {LOGROTATE_CONF}"
    assert re.search(r"\brotate\s+7\b", content), f"'rotate 7' directive missing in {LOGROTATE_CONF}"
    assert re.search(r"\bcompress\b", content), f"'compress' directive missing in {LOGROTATE_CONF}"

    # Ignore comments, require balanced syntax, and require the directives as
    # active entries inside the block for the exact log path.
    active = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert active.count("{") == active.count("}") and active.count("{") > 0, "Unbalanced or missing logrotate block braces"
    path_pattern = rf'(?m)^\s*(?:"{re.escape(LOG_FILE)}"|{re.escape(LOG_FILE)})\s*\{{([^{{}}]*)\}}'
    match = re.search(path_pattern, active)
    assert match, f"No valid logrotate block found for exactly {LOG_FILE}"
    directives = [line.strip() for line in match.group(1).splitlines() if line.strip()]
    assert any(re.fullmatch(r"daily", line) for line in directives), "Active 'daily' directive missing from the log block"
    assert any(re.fullmatch(r"rotate\s+7", line) for line in directives), "Active 'rotate 7' directive missing from the log block"
    assert any(re.fullmatch(r"compress", line) for line in directives), "Active 'compress' directive missing from the log block"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
