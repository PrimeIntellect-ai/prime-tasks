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
import json
import os
import secrets
import signal
import socket
import struct
import subprocess
import time

import pytest
import requests

BINARY = "/home/user/auth_server"
BASE_URL = "http://127.0.0.1:8080"
PASSWORD = "SuperSecretP4ss!"


def listener_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    if not inodes:
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_server():
    for pid in listener_pids():
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)


def wait_for_server():
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                return
        except OSError as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"auth_server did not listen on 127.0.0.1:8080: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def run_submitted_binary():
    assert os.path.exists(BINARY), f"The binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The binary {BINARY} is not executable."
    stop_existing_server()
    proc = subprocess.Popen(
        [BINARY], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, cwd="/home/user"
    )
    wait_for_server()

    owners = listener_pids()
    assert owners, "No process owns the listening socket on port 8080."
    binary_owned_listener = False
    for pid in owners:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                binary_owned_listener = True
                break
        except (FileNotFoundError, PermissionError, OSError):
            pass
    assert binary_owned_listener, "Port 8080 is not served by the submitted auth_server binary."

    yield
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            proc.kill()
        except ProcessLookupError:
            pass


def b64url_encode(value):
    raw = json.dumps(value, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def b64url_decode(value):
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def make_token(header, payload, signature=""):
    return f"{b64url_encode(header)}.{b64url_encode(payload)}.{signature}"


def grants_access(token, raw=False):
    authorization = token if raw else f"Bearer {token}"
    response = requests.get(
        f"{BASE_URL}/flag", headers={"Authorization": authorization}, timeout=5
    )
    return response.status_code == 200 and "ACCESS_GRANTED" in response.text


def assert_rejected(token):
    for raw in (False, True):
        response = requests.get(
            f"{BASE_URL}/flag",
            headers={"Authorization": token if raw else f"Bearer {token}"},
            timeout=5,
        )
        assert not (
            response.status_code == 200 and "ACCESS_GRANTED" in response.text
        ), f"Invalid token was accepted ({'raw' if raw else 'Bearer'}): {token!r}"


def test_auth_server_binary_exists():
    binary_path = "/home/user/auth_server"
    assert os.path.exists(binary_path), f"The binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"The binary {binary_path} is not executable."


def test_auth_server_is_compiled_elf():
    with open(BINARY, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", "auth_server must be a compiled ELF binary, not a script."
    assert len(header) >= 18 and header[5] in (1, 2), "Invalid ELF header."
    endian = "<" if header[5] == 1 else ">"
    elf_type = struct.unpack(endian + "H", header[16:18])[0]
    assert elf_type in (2, 3), "auth_server is not an executable ELF file."


def test_login_endpoint():
    url = f"{BASE_URL}/login"
    data = {"username": "admin", "password": PASSWORD}

    try:
        response = requests.post(url, data=data, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the server at {url}: {e}"

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert "Authorization" in response.headers, "Response is missing the 'Authorization' header."

    token = response.headers["Authorization"].strip()
    if token.lower().startswith("bearer "):
        token = token[7:].strip()
    parts = token.split(".")
    assert len(parts) == 3, "The login Authorization header does not contain a JWT."
    try:
        assert isinstance(json.loads(b64url_decode(parts[0])), dict)
        assert isinstance(json.loads(b64url_decode(parts[1])), dict)
    except Exception as exc:
        pytest.fail(f"The login token is not a structurally valid JWT: {exc}")


def test_login_rejects_bad_credentials():
    bad_passwords = [
        PASSWORD + secrets.token_hex(4),
        secrets.token_urlsafe(18),
        "",
    ]
    for bad_password in bad_passwords:
        response = requests.post(
            f"{BASE_URL}/login",
            data={"username": "admin", "password": bad_password},
            timeout=5,
        )
        assert response.status_code != 200, "An incorrect admin password was accepted."
        assert "Authorization" not in response.headers, "Rejected login returned an Authorization header."

    usernames = ["administrator", "Admin", secrets.token_urlsafe(10)]
    for username in usernames:
        response = requests.post(
            f"{BASE_URL}/login",
            data={"username": username, "password": PASSWORD},
            timeout=5,
        )
        assert response.status_code != 200, f"Non-admin username {username!r} was accepted."
        assert "Authorization" not in response.headers, "Rejected login returned an Authorization header."


def test_flag_endpoint_vulnerability():
    url = f"{BASE_URL}/flag"

    header = {"alg": "none", "typ": "JWT"}
    payload = {"user": "admin"}
    jwt_token = make_token(header, payload)
    headers = {"Authorization": f"Bearer {jwt_token}"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
        if response.status_code != 200 or "ACCESS_GRANTED" not in response.text:
            headers_raw = {"Authorization": jwt_token}
            response = requests.get(url, headers=headers_raw, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the server at {url}: {e}"

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert "ACCESS_GRANTED" in response.text, f"Expected 'ACCESS_GRANTED' in response, got: {response.text}"


def test_random_none_tokens_are_parsed_and_accepted():
    for _ in range(3):
        token = make_token(
            {"typ": "JWT", "alg": "none", "nonce": secrets.token_hex(4)},
            {"user": secrets.token_urlsafe(8), "value": secrets.randbelow(1000000)},
        )
        assert grants_access(token) or grants_access(token, raw=True), "A valid alg:none JWT was rejected."


def test_non_none_algorithms_are_rejected():
    for algorithm in ("HS256", "RS256", "ES256"):
        token = make_token(
            {"alg": algorithm, "typ": "JWT"},
            {"user": secrets.token_urlsafe(8)},
            secrets.token_urlsafe(24),
        )
        assert_rejected(token)

    missing_alg = make_token({"typ": "JWT"}, {"user": "admin"})
    assert_rejected(missing_alg)


def test_malformed_and_missing_tokens_are_rejected():
    response = requests.get(f"{BASE_URL}/flag", timeout=5)
    assert not (response.status_code == 200 and "ACCESS_GRANTED" in response.text), "Missing Authorization was accepted."

    malformed = [
        "",
        "not-a-jwt",
        "one.two",
        "one.two.three.four",
        "@@@.@@@.",
        f"{b64url_encode({'alg': 'none'})}.not-json.",
        f"{base64.urlsafe_b64encode(b'not json').decode().rstrip('=')}.{b64url_encode({'user': 'admin'})}.",
        secrets.token_urlsafe(30),
    ]
    for token in malformed:
        assert_rejected(token)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
