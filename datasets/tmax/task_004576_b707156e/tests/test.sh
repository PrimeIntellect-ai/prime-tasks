#!/bin/bash
set -e
mkdir -p /logs/verifier

wait_port() {
    python3 - "$1" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
deadline = time.time() + 8
while time.time() < deadline:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.3):
            sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit(1)
PY
}

kill_port() {
    python3 - "$1" <<'PY'
import os, signal, sys, time
port = int(sys.argv[1])
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if len(fields) > 9 and int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
            inodes.add(fields[9])
pids = set()
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

# The agent was required to leave both services running.
if ! wait_port 9090 || ! wait_port 8080; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Build and execute the submitted Go sources themselves, preventing a separate
# fixed-response process from satisfying the protocol checks.
if ! go build -o /tmp/verified_backend /app/backend/main.go || \
   ! go build -o /tmp/verified_gateway /app/gateway/main.go; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat <<'GOEOF' > /tmp/verifier_decrypt.go
package main
import (
    "crypto/aes"
    "crypto/cipher"
    "encoding/hex"
    "fmt"
    "os"
)
func main() {
    if len(os.Args) != 3 { os.Exit(2) }
    key := []byte(os.Args[1])
    raw, err := hex.DecodeString(os.Args[2])
    if err != nil { os.Exit(3) }
    block, err := aes.NewCipher(key)
    if err != nil { os.Exit(4) }
    gcm, err := cipher.NewGCM(block)
    if err != nil { os.Exit(5) }
    if len(raw) < gcm.NonceSize() { os.Exit(6) }
    plaintext, err := gcm.Open(nil, raw[:gcm.NonceSize()], raw[gcm.NonceSize():], nil)
    if err != nil { os.Exit(7) }
    fmt.Print(string(plaintext))
}
GOEOF
if ! go build -o /tmp/verifier_decrypt /tmp/verifier_decrypt.go; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

kill_port 8080
kill_port 9090
NEW_MASTER_KEY='f4a8b2c9d3e7f1a5b6c0d4e8f2a9b3c7' nohup /tmp/verified_backend >/tmp/verified_backend.out 2>&1 &
nohup /tmp/verified_gateway >/tmp/verified_gateway.out 2>&1 &
if ! wait_port 9090 || ! wait_port 8080; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import string
import subprocess
import time

import pytest
import requests

NEW_MASTER_KEY = "f4a8b2c9d3e7f1a5b6c0d4e8f2a9b3c7"
GATEWAY_URL = "http://127.0.0.1:8080/api/v1/data"
LOG_FILE = "/app/logs/backend.log"
EXPECTED_CSP = "default-src 'none'; frame-ancestors 'none';"
BACKEND_EXE = "/tmp/verified_backend"


def decrypt_aes_gcm(hex_ct, key):
    assert isinstance(hex_ct, str), "encrypted_data must be a string"
    result = subprocess.run(
        ["/tmp/verifier_decrypt", key, hex_ct],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, "Ciphertext was not valid hex(nonce + AES-GCM ciphertext) for the expected key"
    return result.stdout


def kill_listener(port):
    code = r'''
import os, signal, sys, time
port = int(sys.argv[1]); inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try: lines = open(table).read().splitlines()[1:]
    except OSError: continue
    for line in lines:
        f = line.split()
        if len(f) > 9 and int(f[1].split(":")[1], 16) == port and f[3] == "0A": inodes.add(f[9])
pids = set()
for n in os.listdir("/proc"):
    if not n.isdigit(): continue
    try:
        for fd in os.listdir(f"/proc/{n}/fd"):
            try: target = os.readlink(f"/proc/{n}/fd/{fd}")
            except OSError: continue
            if target.startswith("socket:[") and target[8:-1] in inodes: pids.add(int(n))
    except OSError: pass
for pid in pids:
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
time.sleep(.25)
for pid in pids:
    try: os.kill(pid, signal.SIGKILL)
    except ProcessLookupError: pass
'''
    subprocess.run(["python3", "-c", code, str(port)], check=True)


def wait_port(port):
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.3):
                return
        except OSError:
            time.sleep(.1)
    pytest.fail(f"Service did not begin listening on port {port}")


def post_and_check(payload, key):
    try:
        response = requests.post(GATEWAY_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to gateway at {GATEWAY_URL}: {exc}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    csp_header = response.headers.get("Content-Security-Policy", "")
    assert EXPECTED_CSP in csp_header, f"Missing or incorrect CSP header. Got: {csp_header}"

    try:
        body = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Gateway response is not valid JSON: {response.text}")
    assert "encrypted_data" in body, f"Response JSON missing 'encrypted_data' field: {body}"
    assert decrypt_aes_gcm(body["encrypted_data"], key) == payload["data"]
    return body["encrypted_data"]


def assert_redacted(payloads):
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    contents = open(LOG_FILE, encoding="utf-8").read()
    for payload in payloads:
        assert payload["user_token"] not in contents, "Sensitive data (user_token) was found in the logs!"
    assert "[REDACTED]" in contents, "The string '[REDACTED]' was not found in the logs."

    records = []
    for line in contents.splitlines():
        try:
            value = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        if isinstance(value, dict):
            records.append(value)
    for payload in payloads:
        assert any(r.get("user_token") == "[REDACTED]" and r.get("data") == payload["data"] for r in records), \
            f"No correctly redacted log record was found for data value {payload['data']!r}"


def test_submitted_services_end_to_end_and_key_rotation():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    open(LOG_FILE, "w").close()

    # Retain the original fixed case, then add verifier-generated cases.
    payloads = [{"user_token": "super_secret_xyz_123", "data": "secret_message"}]
    for _ in range(5):
        payloads.append({
            "user_token": "tok_" + secrets.token_hex(18),
            "data": "data_" + secrets.token_urlsafe(24),
        })
    repeated = "repeat_" + secrets.token_urlsafe(18)
    payloads.extend([
        {"user_token": "tok_" + secrets.token_hex(18), "data": repeated},
        {"user_token": "tok_" + secrets.token_hex(18), "data": repeated},
    ])

    ciphertexts = [post_and_check(p, NEW_MASTER_KEY) for p in payloads]
    assert ciphertexts[-1] != ciphertexts[-2], "Repeated plaintexts reused the same nonce/ciphertext"
    assert_redacted(payloads)

    # Restart the submitted backend with an undisclosed, verifier-generated key.
    # This verifies NEW_MASTER_KEY is actually consumed instead of hardcoding the
    # key disclosed in the instruction.
    alphabet = string.ascii_letters + string.digits
    alternate_key = "".join(secrets.choice(alphabet) for _ in range(32))
    kill_listener(9090)
    env = os.environ.copy()
    env["NEW_MASTER_KEY"] = alternate_key
    subprocess.Popen([BACKEND_EXE], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_port(9090)

    alternate_payload = {
        "user_token": "alternate_" + secrets.token_hex(20),
        "data": "rotated_" + secrets.token_urlsafe(30),
    }
    post_and_check(alternate_payload, alternate_key)
    payloads.append(alternate_payload)
    assert_redacted(payloads)
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

# Restore the required final state even after the alternate-key test.
kill_port 9090
NEW_MASTER_KEY='f4a8b2c9d3e7f1a5b6c0d4e8f2a9b3c7' nohup /tmp/verified_backend >/tmp/verified_backend.out 2>&1 &
if ! wait_port 9090 || ! wait_port 8080; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
