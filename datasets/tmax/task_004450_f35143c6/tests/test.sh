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
import hashlib
import os
import random
import re
import signal
import socket
import stat
import string
import subprocess
import time

import pytest
import requests

PAYLOAD_PATH = "/app/payload.bin"
SCRIPT_PATH = "/home/user/delivery.sh"
LOG_PATH = "/home/user/server.log"
EXPECTED_PAYLOAD_CONTENT = "EVASION_STAGE_2_READY"
SERVER_URL = "http://127.0.0.1:8080/payload"
EXPECTED_TOKEN = "6c5ea1f29ba04a58b273b5dfbe74f1b52a1eb2974e11244ab9bce413c2c77d54"
SERVER_PROCESS = None


def derive_token():
    ocr = subprocess.run(
        ["tesseract", "/app/target_info.png", "stdout"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    pins = re.findall(r"(?<!\d)\d{4}(?!\d)", ocr)
    assert pins, f"Could not derive a 4-digit PIN from target_info.png; OCR output was {ocr!r}"

    strings_output = subprocess.run(
        ["strings", "-a", "/app/token_validator"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    salts = re.findall(r"SALT_[A-Z0-9_]+", strings_output)
    assert salts, "Could not derive the salt from token_validator"
    assert "sha256sum" in strings_output, "Could not derive the SHA-256 algorithm from token_validator"
    return hashlib.sha256((pins[0] + salts[0]).encode()).hexdigest()


def request(method="GET", url=SERVER_URL, headers=None):
    try:
        return requests.request(method, url, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the server at {url}. Is it running?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out.")


def listening_socket_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port_8080_listeners():
    inodes = listening_socket_inodes()
    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(victims):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                victims.discard(pid)
        if victims:
            time.sleep(0.5)


def wait_for_server(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() not in (None, 0):
            pytest.fail(f"delivery.sh exited with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("delivery.sh did not start a listener on TCP port 8080")


def test_payload_file_exists_and_content():
    assert os.path.exists(PAYLOAD_PATH), f"File {PAYLOAD_PATH} does not exist."
    assert os.path.isfile(PAYLOAD_PATH), f"{PAYLOAD_PATH} is not a regular file."
    with open(PAYLOAD_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_PAYLOAD_CONTENT, f"Payload content is incorrect. Expected '{EXPECTED_PAYLOAD_CONTENT}', got '{content}'."


def test_payload_file_permissions():
    assert os.path.exists(PAYLOAD_PATH), f"File {PAYLOAD_PATH} does not exist."
    perms = stat.S_IMODE(os.stat(PAYLOAD_PATH).st_mode)
    assert perms == 0o400, f"Payload file permissions are incorrect. Expected 0400, got {oct(perms)}."


def test_required_bash_artifact_and_log_exist():
    script_stat = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(script_stat.st_mode), f"{SCRIPT_PATH} is not a regular file"
    assert not stat.S_ISLNK(script_stat.st_mode), f"{SCRIPT_PATH} must not be a symlink"
    with open(SCRIPT_PATH, encoding="utf-8") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!\s*(?:/usr/bin/env\s+(?:-S\s+)?bash|.*/bash)(?:\s|$)", first_line), "delivery.sh must have a Bash shebang"
    syntax = subprocess.run(["/bin/bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"delivery.sh is not valid Bash: {syntax.stderr}"
    assert re.search(r"X-Evasion-Token", source, re.IGNORECASE), "delivery.sh does not implement the required token header check"
    assert "/payload" in source, "delivery.sh does not implement the required payload route"
    assert "200" in source and "403" in source, "delivery.sh does not implement both required HTTP outcomes"

    active_lines = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    assert not re.search(r"(^|[;&|]\s*|\bexec\s+)(python[0-9.]*|ruby|perl|node|php|busybox\s+httpd)\b", active_lines, re.IGNORECASE), "delivery.sh delegates the server to a prohibited non-Bash implementation"

    log_stat = os.lstat(LOG_PATH)
    assert stat.S_ISREG(log_stat.st_mode), f"{LOG_PATH} is not a regular file"
    assert not stat.S_ISLNK(log_stat.st_mode), f"{LOG_PATH} must not be a symlink"


def test_server_authenticated_request():
    response = request(headers={"X-Evasion-Token": EXPECTED_TOKEN})
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
    assert response.text.strip() == EXPECTED_PAYLOAD_CONTENT, f"Expected response body '{EXPECTED_PAYLOAD_CONTENT}', got '{response.text}'."


def test_server_unauthenticated_request_missing_header():
    response = request()
    assert response.status_code == 403, f"Expected HTTP 403 Forbidden for missing header, got {response.status_code}."


def test_server_unauthenticated_request_wrong_header():
    response = request(headers={"X-Evasion-Token": "invalid_token_12345"})
    assert response.status_code == 403, f"Expected HTTP 403 Forbidden for incorrect token, got {response.status_code}."


def test_execute_delivery_script_and_exercise_general_behavior():
    global SERVER_PROCESS
    derived_token = derive_token()
    assert derived_token == EXPECTED_TOKEN, "The token derived from the supplied artifacts differs from the expected authentication token"

    kill_port_8080_listeners()
    log = open(LOG_PATH, "a")
    SERVER_PROCESS = subprocess.Popen(
        ["/bin/bash", SCRIPT_PATH],
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_for_server(SERVER_PROCESS)

    response = request(headers={"X-Evasion-Token": derived_token})
    assert response.status_code == 200
    assert response.text.strip() == EXPECTED_PAYLOAD_CONTENT

    alphabet = string.ascii_letters + string.digits
    for _ in range(3):
        wrong = "".join(random.SystemRandom().choice(alphabet) for _ in range(48))
        response = request(headers={"X-Evasion-Token": wrong})
        assert response.status_code == 403, f"Random incorrect token was not rejected: {wrong}"

    for suffix in ("x", "-extra"):
        response = request(headers={"X-Evasion-Token": derived_token + suffix})
        assert response.status_code == 403, "Token comparison was not exact"

    for _ in range(3):
        path = "/" + "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(16))
        response = request(url="http://127.0.0.1:8080" + path, headers={"X-Evasion-Token": derived_token})
        assert not (response.status_code == 200 and response.text.strip() == EXPECTED_PAYLOAD_CONTENT), f"Server exposed the payload on unexpected path {path}"

    response = request(method="POST", headers={"X-Evasion-Token": derived_token})
    assert not (response.status_code == 200 and response.text.strip() == EXPECTED_PAYLOAD_CONTENT), "Server exposed the payload for a non-GET request"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
