#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
    test -d /home/user/audit_service
    test -f /home/user/audit_service/Cargo.toml

    python3 - <<'PY'
import json
import os
import subprocess

root = os.path.realpath('/home/user/audit_service')
data = json.loads(subprocess.check_output([
    'cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1',
    '--manifest-path', '/home/user/audit_service/Cargo.toml'
], text=True))

assert data['packages'], 'Cargo project contains no package'
binaries = []
for package in data['packages']:
    for target in package.get('targets', []):
        if 'bin' in target.get('kind', []):
            source = os.path.realpath(target['src_path'])
            assert os.path.commonpath([root, source]) == root, 'Binary source is outside the requested project'
            assert source.endswith('.rs'), 'Binary target is not Rust source'
            assert os.path.isfile(source), f'Missing Rust source: {source}'
            binaries.append(target)
assert binaries, 'Cargo project has no Rust binary target'
PY

    if ! cargo build --offline --manifest-path /home/user/audit_service/Cargo.toml; then
        HOME=/home/user CARGO_HOME=/home/user/.cargo cargo build --offline --manifest-path /home/user/audit_service/Cargo.toml
    fi

    # Stop anything already occupying the required ports, so the tests exercise
    # the submitted Cargo application rather than an unrelated background process.
    python3 - <<'PY'
import glob
import os
import signal
import time

ports = {8080, 8081}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if len(fields) > 9 and fields[3] == '0A':
            port = int(fields[1].rsplit(':', 1)[1], 16)
            if port in ports:
                inodes.add(fields[9])

pids = set()
for fd in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        pids.add(int(fd.split('/')[2]))

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

    nohup cargo run --offline --quiet --manifest-path /home/user/audit_service/Cargo.toml >/tmp/audit_service_verifier.log 2>&1 &
    SERVER_PID=$!

    python3 - <<'PY'
import time

wanted = {8080, 8081}
for _ in range(150):
    listening = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 3 and fields[3] == '0A':
                listening.add(int(fields[1].rsplit(':', 1)[1], 16))
    if wanted <= listening:
        break
    time.sleep(0.1)
else:
    raise AssertionError('Submitted Cargo application did not listen on both ports')
PY

    kill -0 "$SERVER_PID"

    cat <<'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import socket
import requests
import hashlib
import pytest
import secrets
import time

TOKEN = "SECURE_AUDIT_9982"
HTTP_URL = "http://127.0.0.1:8080"
TCP_HOST = "127.0.0.1"
TCP_PORT = 8081

CSP_HEADER_EXPECTED = "default-src 'none'; frame-ancestors 'none';"

def test_http_404_and_csp():
    """Test that a GET request to / returns 404 and includes the CSP header."""
    try:
        response = requests.get(HTTP_URL, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service on port 8080: {e}")

    assert response.status_code == 404, f"Expected 404 Not Found, got {response.status_code}"
    csp = response.headers.get("Content-Security-Policy", "")
    assert csp == CSP_HEADER_EXPECTED, f"Expected CSP header '{CSP_HEADER_EXPECTED}', got '{csp}'"

def test_http_audit_no_token():
    """Test that POST /audit without a token returns 401."""
    try:
        response = requests.post(f"{HTTP_URL}/audit", data="test", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service on port 8080: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"
    csp = response.headers.get("Content-Security-Policy", "")
    assert csp == CSP_HEADER_EXPECTED, f"Expected CSP header '{CSP_HEADER_EXPECTED}', got '{csp}'"

def test_http_audit_with_token():
    """Test that POST /audit with the correct token returns 200 and the correct X-Body-Hash."""
    payload = "test_payload"
    expected_hash = hashlib.sha256(payload.encode()).hexdigest()
    headers = {"Authorization": f"Bearer {TOKEN}"}

    try:
        response = requests.post(f"{HTTP_URL}/audit", headers=headers, data=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service on port 8080: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    csp = response.headers.get("Content-Security-Policy", "")
    assert csp == CSP_HEADER_EXPECTED, f"Expected CSP header '{CSP_HEADER_EXPECTED}', got '{csp}'"

    body_hash = response.headers.get("X-Body-Hash", "")
    assert body_hash == expected_hash, f"Expected X-Body-Hash '{expected_hash}', got '{body_hash}'"

def test_tcp_valid_scan():
    """Test the TCP service with the correct scan command."""
    try:
        with socket.create_connection((TCP_HOST, TCP_PORT), timeout=2) as s:
            s.sendall(f"SCAN {TOKEN}\n".encode())
            data = s.recv(1024).decode()
            assert data == "VALID\n", f"Expected 'VALID\\n', got {repr(data)}"
    except socket.error as e:
        pytest.fail(f"Failed to connect or communicate with TCP service on port 8081: {e}")

def test_tcp_invalid_scan():
    """Test the TCP service with an incorrect scan command."""
    try:
        with socket.create_connection((TCP_HOST, TCP_PORT), timeout=2) as s:
            s.sendall(b"SCAN WRONG\n")
            data = s.recv(1024).decode()
            assert data == "REJECTED\n", f"Expected 'REJECTED\\n', got {repr(data)}"
    except socket.error as e:
        pytest.fail(f"Failed to connect or communicate with TCP service on port 8081: {e}")

def assert_csp(response):
    assert response.headers.get("Content-Security-Policy", "") == CSP_HEADER_EXPECTED

def test_randomized_body_hashes():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    for _ in range(4):
        payload = secrets.token_bytes(37 + secrets.randbelow(220))
        response = requests.post(f"{HTTP_URL}/audit", headers=headers, data=payload, timeout=2)
        assert response.status_code == 200
        assert_csp(response)
        assert response.headers.get("X-Body-Hash", "") == hashlib.sha256(payload).hexdigest()

def test_exact_authorization_validation():
    wrong = secrets.token_urlsafe(24)
    while wrong == TOKEN:
        wrong = secrets.token_urlsafe(24)
    invalid_values = [
        f"Bearer {wrong}",
        f"Bearer {TOKEN}{secrets.token_hex(4)}",
        f"Bearer {secrets.token_hex(4)}{TOKEN}",
        f"bearer {TOKEN}",
        TOKEN,
    ]
    for value in invalid_values:
        response = requests.post(
            f"{HTTP_URL}/audit", headers={"Authorization": value},
            data=secrets.token_bytes(19), timeout=2
        )
        assert response.status_code == 401, f"Authorization value was incorrectly accepted: {value!r}"
        assert_csp(response)

def test_random_other_routes_and_methods_are_404():
    path = "/" + secrets.token_urlsafe(18)
    headers = {"Authorization": f"Bearer {TOKEN}"}
    responses = [
        requests.get(f"{HTTP_URL}/audit", headers=headers, timeout=2),
        requests.post(f"{HTTP_URL}{path}", headers=headers, data=secrets.token_bytes(13), timeout=2),
        requests.put(f"{HTTP_URL}/audit", headers=headers, data=secrets.token_bytes(11), timeout=2),
    ]
    for response in responses:
        assert response.status_code == 404
        assert_csp(response)

def tcp_exchange(message, fragments=False):
    with socket.create_connection((TCP_HOST, TCP_PORT), timeout=2) as s:
        s.settimeout(2)
        if fragments:
            cut = max(1, len(message) // 2)
            s.sendall(message[:cut])
            time.sleep(0.03)
            s.sendall(message[cut:])
        else:
            s.sendall(message)
        chunks = []
        while True:
            part = s.recv(1024)
            if not part:
                break
            chunks.append(part)
        return b"".join(chunks)

def test_tcp_exact_randomized_validation():
    assert tcp_exchange(f"SCAN {TOKEN}\n".encode(), fragments=True) == b"VALID\n"
    wrong = secrets.token_urlsafe(25)
    invalid = [
        f"SCAN {wrong}\n".encode(),
        f"SCAN {TOKEN}{secrets.token_hex(3)}\n".encode(),
        f"SCAN {TOKEN}\nEXTRA".encode(),
        f"scan {TOKEN}\n".encode(),
        secrets.token_bytes(31) + b"\n",
    ]
    for message in invalid:
        assert tcp_exchange(message) == b"REJECTED\n", f"Invalid TCP message accepted: {message!r}"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/audit_service_verifier.log 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
