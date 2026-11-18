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
import random
import re
import secrets
import signal
import socket
import string
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8000/validate"
TOKEN = "SEC-TKN-88A21F9C"
IMAGE = Path("/app/policy_token.png")
SIGNATURE = re.compile(r"(?:0x)?[eE]9\s?[0-9a-fA-F]{8}")


def post(command, token=TOKEN, timeout=5):
    headers = {} if token is None else {"X-Policy-Token": token}
    encoded = base64.b64encode(command.encode("utf-8")).decode("ascii")
    return requests.post(URL, headers=headers, json={"command": encoded}, timeout=timeout)


def listener_entries():
    entries = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                host_hex, port_hex = local_address.rsplit(":", 1)
                if int(port_hex, 16) == 8000 and state == "0A":
                    entries.append((table, host_hex, fields[9]))
    return entries


def pids_for_inode(inode):
    result = []
    target = f"socket:[{inode}]"
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    if os.readlink(fd) == target:
                        result.append(int(proc.name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return result


def listener_pid():
    entries = listener_entries()
    assert len(entries) == 1, f"Expected exactly one listening socket on port 8000, found {entries}"
    table, host_hex, inode = entries[0]
    assert table == "/proc/net/tcp" and host_hex == "0100007F", (
        "Port 8000 must listen exactly on IPv4 address 127.0.0.1"
    )
    pids = pids_for_inode(inode)
    assert len(pids) == 1, f"Could not identify one server process for socket inode {inode}: {pids}"
    return pids[0]


def process_launch_info(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    command = [part.decode(errors="surrogateescape") for part in raw if part]
    assert command, "Listening server has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    environ = os.environ.copy()
    try:
        for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                environ[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return command, cwd, environ


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        if not Path(f"/proc/{pid}").exists():
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def stop_all_port_8000_listeners():
    for _, _, inode in listener_entries():
        for pid in pids_for_inode(inode):
            stop_pid(pid)
    deadline = time.time() + 5
    while listener_entries() and time.time() < deadline:
        time.sleep(0.05)


def launch(command, cwd, environ):
    return subprocess.Popen(
        command,
        cwd=cwd,
        env=environ,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def wait_ready(timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.post(URL, json={"command": "ZWNobyBvaw=="}, timeout=0.5)
            if response.status_code == 401:
                return
            last_error = AssertionError(f"Unexpected readiness status {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Server did not become ready: {last_error}")


def test_missing_token_returns_401():
    """Send POST /validate with no headers. Expect: 401 Unauthorized."""
    try:
        response = requests.post(URL, json={"command": "ZWNobywiaGVsbG8i"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected status code 401 for missing token, but got {response.status_code}. Response: {response.text}"


def test_valid_token_benign_command_returns_200():
    """Send POST /validate with valid token and benign command. Expect: 200 OK."""
    headers = {"X-Policy-Token": TOKEN}
    payload = {"command": "ZWNobywiaGVsbG8i"}
    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 200, f"Expected status code 200 for valid token and benign command, but got {response.status_code}. Response: {response.text}"


def test_valid_token_malicious_command_returns_403():
    """Send POST /validate with valid token and malicious command matching regex. Expect: 403 Forbidden."""
    headers = {"X-Policy-Token": TOKEN}
    payload = {"command": "c2hlbGxjb2RlIGU5IDkwOTBBMUIyIGhlcmU="}
    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 403, f"Expected status code 403 for valid token and malicious command, but got {response.status_code}. Response: {response.text}"


def test_valid_token_malicious_command_with_0x_returns_403():
    """Send POST /validate with valid token and another malicious command matching regex. Expect: 403 Forbidden."""
    headers = {"X-Policy-Token": TOKEN}
    payload = {"command": "YmFkIDB4RTkgMTIzNDU2NzggaW5qZWN0"}
    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 403, f"Expected status code 403 for valid token and malicious command with 0x prefix, but got {response.status_code}. Response: {response.text}"


def test_randomized_authorization_base64_and_regex_behavior():
    rng = random.SystemRandom()

    for _ in range(8):
        wrong_token = "BAD" + secrets.token_hex(10)
        command = "safe-" + secrets.token_urlsafe(18)
        assert post(command, wrong_token).status_code == 401

    malicious = []
    for _ in range(18):
        prefix = rng.choice(["", "0x"])
        opcode = rng.choice(["e9", "E9"])
        spacing = rng.choice(["", " "])
        operand = "".join(rng.choice(string.hexdigits) for _ in range(8))
        command = secrets.token_urlsafe(7) + " " + prefix + opcode + spacing + operand + " " + secrets.token_urlsafe(7)
        assert SIGNATURE.search(command)
        malicious.append(command)

    for command in malicious:
        response = post(command)
        assert response.status_code == 403, f"Regex-matching decoded command was not rejected: {command!r}"

    benign = [
        "e8 12345678",
        "e9 1234567",
        "e9 123456789",
        "0XE9 12345678",
        "0xe9 1234ZZZZ",
        "ordinary command " + secrets.token_urlsafe(30),
    ]
    while len(benign) < 24:
        candidate = "run-" + secrets.token_urlsafe(rng.randint(8, 45))
        if not SIGNATURE.search(candidate):
            benign.append(candidate)

    for command in benign:
        assert not SIGNATURE.search(command)
        response = post(command)
        assert response.status_code == 200, f"Benign decoded command was not allowed: {command!r}"


def test_single_endpoint_and_exact_listener():
    pid = listener_pid()
    command, cwd, _ = process_launch_info(pid)
    executable_text = " ".join(command).lower()
    assert "python" in executable_text or "gunicorn" in executable_text or "flask" in executable_text, (
        f"The listening artifact is not a Python HTTP server: {command}"
    )
    assert os.path.isdir(cwd)

    for _ in range(5):
        path = "/" + secrets.token_urlsafe(12)
        response = requests.post(
            "http://127.0.0.1:8000" + path,
            headers={"X-Policy-Token": TOKEN},
            json={"command": base64.b64encode(b"safe").decode()},
            timeout=5,
        )
        assert response.status_code == 404, f"Unexpected extra POST endpoint {path}: {response.status_code}"

    response = requests.get(URL, headers={"X-Policy-Token": TOKEN}, timeout=5)
    assert response.status_code == 405, f"GET /validate must not be exposed; got {response.status_code}"


def test_zz_server_reloads_token_from_image_using_ocr():
    original_image = IMAGE.read_bytes()
    original_pid = listener_pid()
    command, cwd, environ = process_launch_info(original_pid)
    replacement = "P" + "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(11))
    replacement_process = None

    try:
        subprocess.run(
            [
                "convert", "-size", "200x50", "xc:white", "-font", "DejaVu-Sans",
                "-pointsize", "20", "-fill", "black", "-annotate", "+10+30", replacement,
                str(IMAGE),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        ocr_token = subprocess.check_output(
            ["tesseract", str(IMAGE), "stdout"], stderr=subprocess.DEVNULL, text=True
        ).strip()
        assert ocr_token and ocr_token != TOKEN, f"Could not generate a distinct OCR token: {ocr_token!r}"

        stop_pid(original_pid)
        stop_all_port_8000_listeners()
        replacement_process = launch(command, cwd, environ)
        wait_ready()

        random_command = "ocr-check-" + secrets.token_urlsafe(20)
        assert post(random_command, ocr_token).status_code == 200, (
            "Restarted server did not accept the token OCR-extracted from the replacement image"
        )
        assert post(random_command, TOKEN).status_code == 401, (
            "Restarted server still accepted the old hardcoded token"
        )
    finally:
        stop_all_port_8000_listeners()
        IMAGE.write_bytes(original_image)
        restored = launch(command, cwd, environ)
        try:
            wait_ready()
        except Exception:
            if restored.poll() is None:
                restored.terminate()
            raise
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
