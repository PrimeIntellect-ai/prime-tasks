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
import re
import secrets
import signal
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
EXECUTABLE = "/home/user/server_secure"
SOURCE = "/home/user/src/server.c"
AUTH_OBJECT = "/home/user/auth.o"
LOG_PATH = "/home/user/server.log"
PORT_HEX = "1F90"

SAFE_PATH = "/audit-" + secrets.token_hex(8)
EXTERNAL_HOST = secrets.token_hex(8) + ".example"
RANDOM_SESSION = secrets.token_urlsafe(18)
RANDOM_OVERRIDE = secrets.token_urlsafe(18)
LOG_MARKER = "marker-" + secrets.token_hex(12)


def listening_records():
    records = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            address, port = fields[1].rsplit(":", 1)
            if port.upper() == PORT_HEX:
                records.append((table, address.upper(), fields[9]))
    return records


def owners_of_inode(inode):
    owners = set()
    target = f"socket:[{inode}]"
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            if os.readlink(fd) == target:
                owners.add(int(fd.split("/")[2]))
        except (OSError, ValueError):
            pass
    return owners


def executable_matches(pid):
    try:
        return os.path.samefile(f"/proc/{pid}/exe", EXECUTABLE)
    except OSError:
        return False


def secure_server_pids(require_loopback=True):
    records = listening_records()
    if require_loopback:
        records = [r for r in records if r[0] == "/proc/net/tcp" and r[1] == "0100007F"]
    pids = set()
    for _, _, inode in records:
        pids.update(pid for pid in owners_of_inode(inode) if executable_matches(pid))
    return pids


def all_port_owners():
    pids = set()
    for _, _, inode in listening_records():
        pids.update(owners_of_inode(inode))
    return pids


def stop_port_owners():
    pids = all_port_owners()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_records():
        time.sleep(0.05)
    for pid in all_port_owners():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_records():
        time.sleep(0.05)


def wait_for_secure_listener(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        records = listening_records()
        wildcard = [r for r in records if r[0] == "/proc/net/tcp" and r[1] == "00000000"]
        assert not wildcard, "server_secure listens on all interfaces instead of 127.0.0.1"
        if secure_server_pids():
            return
        if proc.poll() is not None:
            pytest.fail(f"server_secure exited during startup with status {proc.returncode}")
        time.sleep(0.05)
    pytest.fail("server_secure did not bind and listen on 127.0.0.1:8080")


@pytest.fixture(scope="session", autouse=True)
def validate_build_and_run_server():
    assert os.path.exists(EXECUTABLE), f"Missing executable: {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"Missing source file: {SOURCE}"
    assert os.path.isfile(AUTH_OBJECT), f"Missing authentication object: {AUTH_OBJECT}"

    # The agent was instructed to leave server_secure itself running.
    records = listening_records()
    assert records, "Nothing is listening on port 8080"
    assert not any(r[0] == "/proc/net/tcp" and r[1] == "00000000" for r in records), \
        "The server is bound to all interfaces rather than 127.0.0.1"
    assert secure_server_pids(), \
        "The process serving 127.0.0.1:8080 is not /home/user/server_secure"

    # Require the submitted source to compile warning-free while linking auth.o.
    clean_binary = f"/tmp/server-clean-{os.getpid()}"
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", "-Werror", SOURCE, AUTH_OBJECT, "-o", clean_binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"server.c does not compile cleanly with auth.o:\n{result.stdout}{result.stderr}"
    nm = subprocess.run(["nm", EXECUTABLE], capture_output=True, text=True, timeout=10)
    assert nm.returncode == 0 and re.search(r"\b[Tt]\s+check_auth$", nm.stdout, re.MULTILINE), \
        "server_secure does not contain the check_auth implementation from the linked auth module"
    os.unlink(clean_binary)

    # Restart the submitted artifact ourselves so all behavioral checks exercise it.
    stop_port_owners()
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    proc = subprocess.Popen(
        [EXECUTABLE],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_secure_listener(proc)
    yield
    stop_port_owners()
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def get(path, **kwargs):
    try:
        return requests.get(BASE_URL + path, allow_redirects=False, timeout=2, **kwargs)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to server failed: {e}")


def test_executable_exists():
    path = "/home/user/server_secure"
    assert os.path.exists(path), f"Missing executable: {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert secure_server_pids(), "server_secure is not the process serving requests"


def test_open_redirect_malicious():
    response = get("/login?next=http://attacker.com/steal")
    assert response.status_code == 302, f"Expected status 302 for malicious redirect, got {response.status_code}. Response body: {response.text}"
    location = response.headers.get("Location")
    assert location == "/home", f"Expected Location header to be '/home', got '{location}'"


def test_open_redirect_safe():
    response = get("/login?next=/profile")
    assert response.status_code == 302, f"Expected status 302 for safe redirect, got {response.status_code}. Response body: {response.text}"
    location = response.headers.get("Location")
    assert location == "/profile", f"Expected Location header to be '/profile', got '{location}'"


def test_open_redirect_randomized_cases():
    response = get("/login?next=" + SAFE_PATH)
    assert response.status_code == 302
    assert response.headers.get("Location") == SAFE_PATH

    for destination in (
        "http://" + EXTERNAL_HOST + "/steal",
        "https://" + EXTERNAL_HOST + "/steal",
        "//" + EXTERNAL_HOST + "/steal",
    ):
        response = get("/login?next=" + destination)
        assert response.status_code == 302
        assert response.headers.get("Location") == "/home", \
            f"External redirect {destination!r} was not rejected"


def test_auth_module_behavior_with_derived_inputs():
    response = get("/admin", headers={"Cookie": f"dev_override={RANDOM_OVERRIDE}"})
    assert response.status_code == 401, "An arbitrary override token was accepted"

    response = get("/admin", headers={"Cookie": "dev_override=OmegaProtocol99"})
    assert response.status_code == 200, "The developer override recognized by auth.o was not accepted"


def test_auth_and_logging():
    headers = {
        "Cookie": "dev_override=OmegaProtocol99; session_id=12345ABC;"
    }
    response = get("/admin", headers=headers)
    assert response.status_code == 200, f"Expected status 200 for authenticated request, got {response.status_code}. Response body: {response.text}"

    time.sleep(0.5)
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    assert "OmegaProtocol99" not in log_content, "Log file leaked the sensitive dev_override token 'OmegaProtocol99'."
    assert "12345ABC" not in log_content, "Log file leaked the sensitive session_id '12345ABC'."
    assert "dev_override=[REDACTED]" in log_content, "Log file does not show 'dev_override=[REDACTED]'."
    assert "session_id=[REDACTED]" in log_content, "Log file does not show 'session_id=[REDACTED]'."


def test_random_cookie_values_are_redacted_from_real_log_input():
    cookie = (
        f"audit_marker={LOG_MARKER}; "
        f"session_id={RANDOM_SESSION}; "
        f"dev_override={RANDOM_OVERRIDE}"
    )
    response = get("/audit-log", headers={"Cookie": cookie})
    assert response.status_code == 401
    time.sleep(0.2)

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    assert LOG_MARKER in log_content, "The actual randomized request was not written to server.log"
    assert RANDOM_SESSION not in log_content, "A randomized session_id value was leaked"
    assert RANDOM_OVERRIDE not in log_content, "A randomized dev_override value was leaked"
    assert "session_id=[REDACTED]" in log_content
    assert "dev_override=[REDACTED]" in log_content
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
