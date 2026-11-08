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
import shutil
import signal
import subprocess
import time

import pytest
import requests

SPEC_IMAGE = "/app/config_spec.png"
SERVICE_DATA_DIR = "/home/user/service_data"
PROVISION_SCRIPT = "/home/user/provision.sh"
SERVER_SCRIPT = os.path.join(SERVICE_DATA_DIR, "server.py")
PID_FILE = os.path.join(SERVICE_DATA_DIR, "server.pid")
LOGROTATE_CONF = os.path.join(SERVICE_DATA_DIR, "logrotate.conf")
ACCESS_LOG = os.path.join(SERVICE_DATA_DIR, "access.log")


def read_spec():
    result = subprocess.run(
        ["tesseract", SPEC_IMAGE, "stdout"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"tesseract failed: {result.stderr}"
    port_match = re.search(r"PORT\s*:\s*(\d+)", result.stdout, re.IGNORECASE)
    token_match = re.search(r"TOKEN\s*:\s*([^\s]+)", result.stdout, re.IGNORECASE)
    assert port_match, f"Could not extract PORT from specification: {result.stdout!r}"
    assert token_match, f"Could not extract TOKEN from specification: {result.stdout!r}"
    return int(port_match.group(1)), token_match.group(1)


PORT, TOKEN = read_spec()
BASE_URL = f"http://127.0.0.1:{PORT}/"


def process_alive(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat", "r") as f:
            return f.read().split()[2] != "Z"
    except (OSError, FileNotFoundError, IndexError):
        return False


def stop_pid(pid):
    if pid <= 1 or not process_alive(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 2
    while time.time() < deadline and process_alive(pid):
        time.sleep(0.05)
    if process_alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def listener_socket_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            if int(fields[1].rsplit(":", 1)[1], 16) == port:
                found.add(fields[9])
    return found


def pid_socket_inodes(pid):
    found = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except FileNotFoundError:
        return found
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            found.add(match.group(1))
    return found


def pid_listens_on_all_interfaces(pid, port):
    owned = pid_socket_inodes(pid)
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A" or fields[9] not in owned:
                continue
            address, port_hex = fields[1].split(":")
            if int(port_hex, 16) == port and set(address) <= {"0"}:
                return True
    return False


def kill_existing_service():
    if os.path.isfile(PID_FILE):
        try:
            with open(PID_FILE, "r") as f:
                value = f.read().strip()
            if value.isdigit():
                stop_pid(int(value))
        except OSError:
            pass

    # Also remove any manually launched listener not represented by server.pid.
    inodes = listener_socket_inodes(PORT)
    if inodes:
        for entry in os.listdir("/proc"):
            if entry.isdigit() and pid_socket_inodes(int(entry)) & inodes:
                stop_pid(int(entry))


def read_pid():
    assert os.path.isfile(PID_FILE), f"{PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file does not contain a valid PID: {value}"
    return int(value)


def wait_for_service(pid, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process_alive(pid) and pid_listens_on_all_interfaces(pid, PORT):
            return
        time.sleep(0.1)
    pytest.fail(f"PID {pid} did not listen on 0.0.0.0:{PORT}")


def run_provision():
    return subprocess.run(
        [PROVISION_SCRIPT], capture_output=True, text=True, timeout=10
    )


def test_provision_script_exists_and_executable_and_creates_service():
    assert os.path.isfile(PROVISION_SCRIPT), f"{PROVISION_SCRIPT} does not exist."
    assert os.access(PROVISION_SCRIPT, os.X_OK), f"{PROVISION_SCRIPT} is not executable."

    kill_existing_service()
    shutil.rmtree(SERVICE_DATA_DIR, ignore_errors=True)

    result = run_provision()
    assert result.returncode == 0, f"provision.sh failed. stderr: {result.stderr}"
    assert os.path.isdir(SERVICE_DATA_DIR), f"{SERVICE_DATA_DIR} was not created."
    assert os.path.isfile(SERVER_SCRIPT), f"{SERVER_SCRIPT} was not created."
    assert not os.path.islink(SERVER_SCRIPT), f"{SERVER_SCRIPT} must be a generated file, not a symlink."

    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", SERVER_SCRIPT],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"server.py is not valid Python: {compile_result.stderr}"

    pid = read_pid()
    wait_for_service(pid)
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert SERVER_SCRIPT in cmdline, f"Recorded PID is not executing {SERVER_SCRIPT}: {cmdline}"


def test_http_server_unauthorized():
    try:
        response = requests.get(BASE_URL, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server on {BASE_URL}: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for unauthorized request, got {response.status_code}"


def test_http_server_authorized():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.get(BASE_URL, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server on {BASE_URL}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 for authorized request, got {response.status_code}"
    assert response.text.strip() == "Authorized", f"Expected body 'Authorized', got '{response.text}'"


def test_logrotate_conf():
    assert os.path.isfile(LOGROTATE_CONF), f"{LOGROTATE_CONF} does not exist."
    with open(LOGROTATE_CONF, "r") as f:
        content = f.read()

    # Remove comments so required directives cannot be supplied by comments.
    lines = []
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            lines.append(line)

    path_pattern = re.compile(rf'^(?:"{re.escape(ACCESS_LOG)}"|{re.escape(ACCESS_LOG)})\s*(\{{)?$')
    start = None
    for index, line in enumerate(lines):
        match = path_pattern.fullmatch(line)
        if match:
            if match.group(1):
                start = index + 1
            elif index + 1 < len(lines) and lines[index + 1] == "{":
                start = index + 2
            break
    assert start is not None, f"logrotate.conf does not contain a valid stanza targeting {ACCESS_LOG}."

    stanza = []
    depth = 1
    for line in lines[start:]:
        depth += line.count("{") - line.count("}")
        if depth == 0:
            break
        assert depth == 1, "Malformed or nested logrotate stanza."
        stanza.append(line)
    assert depth == 0, "logrotate.conf has an unclosed stanza."

    assert any(re.fullmatch(r"daily", x) for x in stanza), "logrotate.conf missing 'daily' directive."
    assert any(re.fullmatch(r"rotate\s+3", x) for x in stanza), "logrotate.conf missing 'rotate 3' directive."
    assert any(re.fullmatch(r"compress", x) for x in stanza), "logrotate.conf missing 'compress' directive."
    assert any(re.fullmatch(r"create\s+0?644(?:\s+\S+\s+\S+)?", x) for x in stanza), "logrotate.conf missing 'create 0644' directive."

    # If a system parser is available, also require the complete file to parse.
    logrotate = shutil.which("logrotate")
    if logrotate:
        parsed = subprocess.run(
            [logrotate, "--debug", "--state", "/tmp/logrotate-test-state", LOGROTATE_CONF],
            capture_output=True,
            text=True,
        )
        assert parsed.returncode == 0, f"Invalid logrotate configuration: {parsed.stderr}"


def test_access_log_exists_and_is_server_output_target():
    assert os.path.isfile(ACCESS_LOG), f"{ACCESS_LOG} does not exist."
    pid = read_pid()
    expected = os.stat(ACCESS_LOG)
    for fd in (1, 2):
        actual = os.stat(f"/proc/{pid}/fd/{fd}")
        assert (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino), \
            f"Server fd {fd} is not redirected to {ACCESS_LOG}."
        with open(f"/proc/{pid}/fdinfo/{fd}", "r") as f:
            flags_match = re.search(r"^flags:\s*([0-7]+)$", f.read(), re.MULTILINE)
        assert flags_match and int(flags_match.group(1), 8) & os.O_APPEND, \
            f"Server fd {fd} is not opened in append mode."


def test_idempotency():
    initial_pid = str(read_pid())
    result = run_provision()
    assert result.returncode == 0, f"provision.sh failed on second run. stderr: {result.stderr}"
    second_pid = str(read_pid())
    assert initial_pid == second_pid, "PID changed after running provision.sh a second time. The script is not idempotent."


def test_server_still_running_after_idempotency_check():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.get(BASE_URL, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Server is no longer reachable after running provision.sh a second time: {e}")
    assert response.status_code == 200, "Server did not return 200 OK after idempotency check."


def test_stale_pid_is_cleaned_and_service_restarted():
    old_pid = read_pid()
    stop_pid(old_pid)
    assert not process_alive(old_pid), "Could not stop the original server for stale-PID test."
    # Deliberately retain server.pid so provision.sh must recognize it as stale.
    assert os.path.isfile(PID_FILE)

    result = run_provision()
    assert result.returncode == 0, f"provision.sh failed with stale PID file. stderr: {result.stderr}"
    new_pid = read_pid()
    assert new_pid != old_pid, "provision.sh did not replace the stale PID."
    wait_for_service(new_pid)

    response = requests.get(
        BASE_URL,
        headers={"Authorization": f"Bearer {TOKEN}"},
        timeout=2,
    )
    assert response.status_code == 200
    assert response.text.strip() == "Authorized"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
