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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import socket
import subprocess
import time
import secrets
import re

import pytest
import requests
import urllib3
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

APP_DIR = "/home/user/app"
BACKEND_SOURCE = os.path.join(APP_DIR, "backend.c")
START_SCRIPT = os.path.join(APP_DIR, "start.sh")
NGINX_URL = "https://127.0.0.1:8443/auth"
BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = 8081
KEY = b"0123456789abcdef"
IV = b"abcdef9876543210"


def listening_entries(port):
    entries = []
    for path, family in (("/proc/net/tcp", "ipv4"), ("/proc/net/tcp6", "ipv6")):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_addr, local_port = fields[1].split(":")
                    if int(local_port, 16) == port and fields[3] == "0A":
                        entries.append((family, local_addr, fields[9]))
        except FileNotFoundError:
            pass
    return entries


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listening_entries(port):
            return
        time.sleep(0.1)
    raise AssertionError(f"Nothing started listening on port {port}.")


def kill_port_listeners(ports):
    wanted = set()
    for port in ports:
        wanted.update(entry[2] for entry in listening_entries(port))

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for sig in (15, 9):
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2
        while time.time() < deadline and any(listening_entries(p) for p in ports):
            time.sleep(0.1)
        if not any(listening_entries(p) for p in ports):
            return


def assert_loopback_listener(port):
    entries = listening_entries(port)
    assert entries, f"No listener found on port {port}."
    assert all(family == "ipv4" and address == "0100007F" for family, address, _ in entries), \
        f"Port {port} must be bound only to IPv4 127.0.0.1; found {entries}."


def encrypt_token(token):
    plaintext = token.encode("ascii")
    pad_len = 16 - (len(plaintext) % 16)
    padded = plaintext + bytes([pad_len] * pad_len)
    cipher = Cipher(algorithms.AES(KEY), modes.CBC(IV), backend=default_backend())
    encryptor = cipher.encryptor()
    return encryptor.update(padded) + encryptor.finalize()


def check_backend_token(token):
    ciphertext = encrypt_token(token)
    try:
        with socket.create_connection((BACKEND_HOST, BACKEND_PORT), timeout=5) as s:
            s.settimeout(5)
            s.sendall(ciphertext)
            response = s.recv(4096).decode("utf-8", errors="strict")
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to backend at {BACKEND_HOST}:{BACKEND_PORT}.")
    except socket.timeout:
        pytest.fail("Backend connection timed out.")

    assert "Set-Cookie: session=" in response, "Backend did not return the expected Set-Cookie header."
    assert "Secure" in response and "HttpOnly" in response, "Cookie is missing Secure or HttpOnly flags."
    expected = f"Set-Cookie: session={token}; Secure; HttpOnly"
    assert re.search(r"(?:^|\r?\n)" + re.escape(expected) + r"(?:\r?\n|$)", response), \
        f"Backend did not return the decrypted token in the exact cookie format. Response was {response!r}."


@pytest.fixture(scope="session", autouse=True)
def compile_source_and_start_services():
    assert os.path.isfile(BACKEND_SOURCE), f"File {BACKEND_SOURCE} does not exist."
    assert os.path.isfile(START_SCRIPT), f"Startup script {START_SCRIPT} does not exist."

    compiled = "/tmp/backend_compiled_from_submission"
    result = subprocess.run(
        ["gcc", BACKEND_SOURCE, "-o", compiled, "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"backend.c failed to compile with OpenSSL: {result.stderr}"

    kill_port_listeners([8081, 8443])
    source_process = subprocess.Popen(
        [compiled], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_port(8081)
        assert source_process.poll() is None, "The backend compiled from backend.c exited immediately."
        assert_loopback_listener(8081)
        check_backend_token("source_" + secrets.token_hex(8))
        check_backend_token("verify_" + secrets.token_hex(11))
    finally:
        if source_process.poll() is None:
            source_process.terminate()
            try:
                source_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                source_process.kill()
                source_process.wait(timeout=2)
        kill_port_listeners([8081, 8443])

    start_process = subprocess.Popen(
        ["bash", START_SCRIPT],
        cwd=APP_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(0.5)
    if start_process.poll() is not None:
        assert start_process.returncode == 0, f"start.sh exited with status {start_process.returncode}."
    wait_for_port(8081)
    wait_for_port(8443)
    yield


def test_ssh_key_permissions():
    id_rsa_path = os.path.join(APP_DIR, ".ssh", "id_rsa")
    assert os.path.isfile(id_rsa_path), f"SSH private key {id_rsa_path} does not exist."
    permissions = stat.S_IMODE(os.stat(id_rsa_path).st_mode)
    assert permissions == 0o600, f"Expected {id_rsa_path} to have 0600 permissions, got {oct(permissions)}."


def test_ssh_public_key_permissions():
    public_path = os.path.join(APP_DIR, ".ssh", "id_rsa.pub")
    assert os.path.isfile(public_path), f"SSH public key {public_path} does not exist."
    permissions = stat.S_IMODE(os.stat(public_path).st_mode)
    assert permissions == 0o644, f"Expected {public_path} to have 0644 permissions, got {oct(permissions)}."


def test_services_are_loopback_only():
    assert_loopback_listener(8081)
    assert_loopback_listener(8443)


def test_nginx_rejects_without_header():
    try:
        response = requests.get(NGINX_URL, verify=False, timeout=5)
        assert response.status_code in [400, 403], \
            f"Expected Nginx to reject request without header with 400 or 403, got {response.status_code}."
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to Nginx on port 8443. Is it running?")


def test_nginx_accepts_with_header():
    headers = {"X-Auditor-Auth": "true"}
    try:
        response = requests.get(NGINX_URL, headers=headers, verify=False, timeout=5)
        assert response.status_code not in [400, 403], f"Nginx rejected valid request with {response.status_code}."
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to Nginx on port 8443.")


def test_backend_aes_decryption():
    check_backend_token("test_token_12345")
    check_backend_token("runtime_" + secrets.token_hex(10))


def test_backend_source_code():
    assert os.path.isfile(BACKEND_SOURCE), f"File {BACKEND_SOURCE} does not exist."
    with open(BACKEND_SOURCE, "r") as f:
        content = f.read()
    assert "<openssl/aes.h>" in content or "<openssl/evp.h>" in content, \
        "Backend source does not seem to include OpenSSL headers."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
