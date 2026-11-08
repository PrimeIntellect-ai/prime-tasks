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
import base64
import os
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

SECRET = "zk9_f83jf92_git_leak_99"
AUTH_HEADER = {"Authorization": f"Bearer {SECRET}"}
BASE_URL = "http://127.0.0.1:8080/api/v1/auth"
APP_DIR = "/app/auth-service"


def port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def stop_port_listener(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1] == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (OSError, ProcessLookupError, PermissionError):
            pass

    deadline = time.time() + 5
    while time.time() < deadline and port_open(port):
        time.sleep(0.1)
    if port_open(port):
        raise AssertionError(f"Could not stop the previous listener on port {port}")


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    # Preserve the original assertions that the agent left both services running.
    assert port_open(6380), "Redis server is not listening on 127.0.0.1:6380."
    assert port_open(8080), "Rust service is not listening on 127.0.0.1:8080."

    env_path = os.path.join(APP_DIR, ".env")
    assert os.path.isfile(env_path), f"{env_path} is missing."
    with open(env_path) as handle:
        env_content = handle.read()
    assert f"SECRET_API_KEY={SECRET}" in env_content, \
        "The .env file does not contain the correct SECRET_API_KEY."

    source_path = os.path.join(APP_DIR, "src/main.rs")
    assert os.path.isfile(source_path), "src/main.rs is missing."
    with open(source_path) as handle:
        source = handle.read()
    lowered = source.lower()
    assert "base64" in lowered and re.search(r"\bdecode\s*\(", source), \
        "The submitted handler does not perform Base64 decoding."
    assert "utf8" in lowered or "utf_8" in lowered, \
        "The submitted handler does not perform UTF-8 conversion."

    subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=APP_DIR,
        check=True,
        timeout=240,
    )

    # Execute the artifact compiled from the submitted source, rather than trusting
    # whichever process the agent happened to leave on the HTTP port.
    stop_port_listener(8080)
    executable = os.path.join(APP_DIR, "target/debug/auth-service")
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), \
        "The compiled auth-service executable is missing."
    subprocess.Popen(
        [executable],
        cwd=APP_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline and not port_open(8080):
        time.sleep(0.1)
    assert port_open(8080), "The compiled Rust service did not start on port 8080."
    yield


def post(body, headers=AUTH_HEADER):
    try:
        return requests.post(BASE_URL, json=body, headers=headers, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Request failed: {exc}")


def assert_status(body, expected):
    response = post(body)
    assert response.status_code == expected, \
        f"Expected {expected}, got {response.status_code} for {body!r}. Response: {response.text}"


def test_env_file_exists_and_contains_secret():
    env_path = os.path.join(APP_DIR, ".env")
    assert os.path.isfile(env_path), f"{env_path} is missing."
    with open(env_path) as handle:
        content = handle.read()
    assert f"SECRET_API_KEY={SECRET}" in content


def test_redis_running():
    assert port_open(6380), "Redis server is not listening on 127.0.0.1:6380."


def test_rust_service_running():
    assert port_open(8080), "Rust service is not listening on 127.0.0.1:8080."


def test_valid_payload():
    assert_status({"client_id": "client_1", "payload": "SGVsbG8="}, 200)


def test_missing_client_id():
    assert_status({"payload": "SGVsbG8="}, 400)


def test_unpadded_base64_is_bad_request():
    # The instruction explicitly classifies unpadded Base64 as an edge case that
    # must return 400 rather than panic.
    assert_status({"client_id": "client_2", "payload": "SGVsbG8"}, 400)


def test_invalid_utf8_base64():
    assert_status({"client_id": "client_3", "payload": "//5I"}, 200)


def test_random_valid_base64_and_lossy_utf8():
    # Answers are derived at verification time. Arbitrary decoded bytes, including
    # guaranteed-invalid UTF-8, are valid Base64 and must be handled lossily.
    for index in range(12):
        raw = b"\xff" + os.urandom(index + 1)
        encoded = base64.b64encode(raw).decode("ascii")
        assert_status({"client_id": f"random-{index}", "payload": encoded}, 200)


def test_random_unpadded_base64_rejected():
    # Use lengths that necessarily produce '=' padding, then remove it.
    for index, length in enumerate((1, 2, 4, 5, 7, 8, 10, 11)):
        encoded = base64.b64encode(os.urandom(length)).decode("ascii")
        assert encoded.endswith("=")
        unpadded = encoded.rstrip("=")
        assert_status({"client_id": f"unpadded-{index}", "payload": unpadded}, 400)


def test_random_malformed_base64_rejected():
    for index in range(10):
        encoded = base64.b64encode(os.urandom(index + 3)).decode("ascii")
        position = len(encoded) // 2
        malformed = encoded[:position] + "!" + encoded[position + 1:]
        assert_status({"client_id": f"malformed-{index}", "payload": malformed}, 400)

    for malformed in ("A", "A===", "====", "SG=VsbG8=", "SGVsbG8==", "***="):
        assert_status({"client_id": "bad-padding", "payload": malformed}, 400)


def test_missing_and_wrongly_typed_fields_rejected():
    cases = [
        {"client_id": "client"},
        {},
        {"client_id": None, "payload": "SGVsbG8="},
        {"client_id": 7, "payload": "SGVsbG8="},
        {"client_id": "client", "payload": None},
        {"client_id": "client", "payload": ["SGVsbG8="]},
    ]
    for body in cases:
        assert_status(body, 400)


def test_service_survives_edge_cases():
    assert_status({"client_id": "still-alive", "payload": base64.b64encode(b"ok").decode("ascii")}, 200)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
