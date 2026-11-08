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
import stat
import subprocess
import time
import uuid

import pytest
import requests

PORT = 8088
URL = f"http://127.0.0.1:{PORT}"
SECRET = "R0ll0ut_S3cr3t"
UPSTREAM = "127.0.0.1:9099"
PROXY_SCRIPT = "/home/user/proxy.py"
DEPLOY_SCRIPT = "/home/user/deploy.sh"
ACCESS_LOG = "/home/user/access.log"
ARCHIVE_DIR = "/home/user/archive"


def live_process_with_arg(required_arg):
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r") as f:
                if f.read().split()[2] == "Z":
                    continue
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            if required_arg in args:
                return True
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
            pass
    return False


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line for line in f.read().splitlines() if line.strip()]


def test_required_artifacts_and_processes_exist():
    for path in (PROXY_SCRIPT, DEPLOY_SCRIPT):
        assert os.path.exists(path), f"Required artifact {path} does not exist"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required artifact {path} is not a regular file"
        assert os.path.getsize(path) > 0, f"Required artifact {path} is empty"

    py_check = subprocess.run(
        ["python3", "-m", "py_compile", PROXY_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert py_check.returncode == 0, f"proxy.py is not valid Python: {py_check.stderr}"

    bash_check = subprocess.run(
        ["bash", "-n", DEPLOY_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert bash_check.returncode == 0, f"deploy.sh is not valid Bash: {bash_check.stderr}"

    assert live_process_with_arg(PROXY_SCRIPT), "No live process is running /home/user/proxy.py"
    assert live_process_with_arg(DEPLOY_SCRIPT), "No live deployment/rotation process from /home/user/deploy.sh is running"


def test_proxy_auth_missing():
    """Test that requests without the X-Deploy-Auth header return 401 Unauthorized."""
    try:
        resp = requests.get(f"{URL}/test1", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to proxy: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {resp.status_code}"


def test_proxy_auth_wrong():
    """Test that requests with an incorrect X-Deploy-Auth header return 401 Unauthorized."""
    try:
        resp = requests.get(f"{URL}/test2", headers={"X-Deploy-Auth": "WrongKey"}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to proxy: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for wrong auth, got {resp.status_code}"


def test_proxy_auth_correct():
    """Test that requests with the correct X-Deploy-Auth header return 200 OK and the correct JSON payload."""
    try:
        resp = requests.get(f"{URL}/target", headers={"X-Deploy-Auth": SECRET}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to proxy: {e}")
    assert resp.status_code == 200, f"Expected 200 OK for correct auth, got {resp.status_code}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response was not valid JSON")

    assert data.get("status") == "routed", f"Expected status 'routed', got {data.get('status')}"
    assert data.get("upstream") == UPSTREAM, f"Expected upstream '{UPSTREAM}', got {data.get('upstream')}"
    assert data == {"status": "routed", "upstream": UPSTREAM}, f"Unexpected JSON payload: {data}"


def test_log_rotation_and_format():
    """Test that the log rotation daemon works and logs are formatted correctly."""
    for i in range(6):
        try:
            requests.get(f"{URL}/rot_test_{i}", headers={"X-Deploy-Auth": SECRET}, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to proxy during log rotation test: {e}")

    time.sleep(3.5)

    archive_path = "/home/user/archive/access.log.1"
    access_log_path = "/home/user/access.log"

    assert os.path.exists(archive_path), f"Log archive {archive_path} does not exist after rotation. Ensure the daemon is running and rotating files > 5 lines."

    archived_lines = read_nonempty_lines(archive_path)
    assert len(archived_lines) >= 5, f"Expected at least 5 lines in {archive_path}, got {len(archived_lines)}"

    log_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \| X-Deploy-Auth: .* \| Path: /.*$")
    for line in archived_lines:
        assert log_pattern.match(line), f"Log line does not match expected format: {line}"

    assert os.path.exists(access_log_path), f"Access log {access_log_path} does not exist"
    access_lines = read_nonempty_lines(access_log_path)
    for line in access_lines:
        assert log_pattern.match(line), f"Log line does not match expected format: {line}"


def test_real_rotation_shifts_history_and_logs_none():
    """Create fresh history and prove that the live daemon rotates and shifts it."""
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    for suffix in ("1", "2", "3"):
        try:
            os.remove(os.path.join(ARCHIVE_DIR, f"access.log.{suffix}"))
        except FileNotFoundError:
            pass

    with open(ACCESS_LOG, "w"):
        pass
    with open(os.path.join(ARCHIVE_DIR, "access.log.1"), "w") as f:
        f.write("OLDER_ONE_SENTINEL\n")
    with open(os.path.join(ARCHIVE_DIR, "access.log.2"), "w") as f:
        f.write("OLDER_TWO_SENTINEL\n")

    token = uuid.uuid4().hex
    paths = [f"/dynamic_{token}_{i}" for i in range(6)]
    wrong_value = f"wrong_{uuid.uuid4().hex}"
    requests_to_make = [
        (paths[0], None, 401),
        (paths[1], wrong_value, 401),
        (paths[2], SECRET, 200),
        (paths[3], SECRET, 200),
        (paths[4], SECRET, 200),
        (paths[5], SECRET, 200),
    ]

    for path, auth, expected_status in requests_to_make:
        headers = {} if auth is None else {"X-Deploy-Auth": auth}
        try:
            resp = requests.get(URL + path, headers=headers, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed dynamic request {path}: {e}")
        assert resp.status_code == expected_status
        if expected_status == 200:
            assert resp.json() == {"status": "routed", "upstream": UPSTREAM}

    deadline = time.time() + 5.5
    new_archive = os.path.join(ARCHIVE_DIR, "access.log.1")
    shifted_one = os.path.join(ARCHIVE_DIR, "access.log.2")
    shifted_two = os.path.join(ARCHIVE_DIR, "access.log.3")
    while time.time() < deadline:
        if os.path.exists(new_archive) and os.path.exists(shifted_one) and os.path.exists(shifted_two):
            if "OLDER_ONE_SENTINEL" in open(shifted_one).read() and "OLDER_TWO_SENTINEL" in open(shifted_two).read():
                break
        time.sleep(0.2)

    assert os.path.exists(new_archive), "The live daemon did not create access.log.1"
    assert os.path.exists(shifted_one), "The live daemon did not shift access.log.1 to access.log.2"
    assert os.path.exists(shifted_two), "The live daemon did not shift access.log.2 to access.log.3"
    with open(shifted_one) as f:
        assert f.read().strip() == "OLDER_ONE_SENTINEL", "Existing .1 log was not shifted intact to .2"
    with open(shifted_two) as f:
        assert f.read().strip() == "OLDER_TWO_SENTINEL", "Existing .2 log was not shifted intact to .3"

    archived_lines = read_nonempty_lines(new_archive)
    line_pattern = re.compile(
        r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \| X-Deploy-Auth: (.*) \| Path: (/.+)$"
    )
    observed = {}
    for line in archived_lines:
        match = line_pattern.match(line)
        assert match, f"Log line does not match the required exact format: {line}"
        observed[match.group(2)] = match.group(1)

    assert observed.get(paths[0]) == "NONE", "A request with no X-Deploy-Auth header was not logged as NONE"
    assert observed.get(paths[1]) == wrong_value, "Incorrect authentication header value was not logged exactly"
    for path in paths[2:]:
        assert observed.get(path) == SECRET, f"Authenticated dynamic request {path} was not logged exactly"

    assert os.path.exists(ACCESS_LOG), "Rotation did not create a fresh access.log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
