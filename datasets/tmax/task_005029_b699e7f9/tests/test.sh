#!/bin/bash
mkdir -p /logs/verifier
RESULT=1

cat << 'TEST_EOF' > /tmp/test_original_state.py
import os
import urllib.request
import urllib.error
import base64
import json
import pytest

def test_status_file():
    """Test that the status.txt file exists and contains DONE."""
    status_file = "/home/user/status.txt"
    assert os.path.isfile(status_file), f"Status file missing: {status_file}"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "DONE", f"Expected status file to contain 'DONE', got '{content}'"

def test_server_functionality():
    """Test the server decoding, config file creation, and rate limiting."""
    payload_text = "target_app=VerificationApp".encode('utf-16le')
    b64_payload = base64.b64encode(payload_text).decode('ascii')
    json_data = json.dumps({"config": b64_payload}).encode('utf-8')

    # Send 3 successful requests
    for i in range(3):
        req = urllib.request.Request("http://127.0.0.1:8080", data=json_data, method="POST")
        req.add_header('Content-Type', 'application/json')
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                assert response.status == 200, f"Request {i+1} failed with status {response.status}"
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to connect to server or request {i+1} failed: {e}")

    # Verify config.mk was created with the correct content
    config_file = "/home/user/config.mk"
    assert os.path.isfile(config_file), f"Config file missing: {config_file}"
    with open(config_file, "r") as f:
        content = f.read().strip()
    assert content == "TARGET := VerificationApp", f"Unexpected config.mk content: {content}"

    # 4th request should be rate limited and return HTTP 429
    req = urllib.request.Request("http://127.0.0.1:8080", data=json_data, method="POST")
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            pytest.fail("4th request was not rate limited (expected HTTP 429)")
    except urllib.error.HTTPError as e:
        assert e.code == 429, f"Expected HTTP 429 Too Many Requests, got {e.code}"
    except Exception as e:
        pytest.fail(f"Unexpected error on 4th request: {e}")
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short 2>&1; then
    RESULT=0
fi

stop_listener() {
    python3 - "$1" <<'PY'
import os
import signal
import sys

sig = getattr(signal, sys.argv[1])
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].upper().endswith(":1F90") and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                link = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if link.startswith("socket:[") and link[8:-1] in inodes:
                try:
                    os.kill(int(name), sig)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
}

if [ "$RESULT" -eq 1 ]; then
    # Re-run the submitted artifact itself rather than trusting an unrelated process.
    stop_listener SIGTERM
    sleep 0.5
    stop_listener SIGKILL
    sleep 0.3

    (cd /home/user && exec python3 /home/user/server.py >/tmp/submitted_server.log 2>&1) &
    SERVER_PID=$!
    READY=0
    for _ in $(seq 1 50); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            break
        fi
        if python3 - <<'PY'
import socket
try:
    with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
        pass
except OSError:
    raise SystemExit(1)
PY
        then
            READY=1
            break
        fi
        sleep 0.1
    done

    if [ "$READY" -ne 1 ] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat /tmp/submitted_server.log 2>/dev/null || true
        RESULT=0
    fi
fi

if [ "$RESULT" -eq 1 ]; then
cat << 'TEST_EOF' > /tmp/test_extended.py
import base64
import http.client
import json
import os
import secrets
import time

SERVER = "127.0.0.1"
CONFIG = "/home/user/config.mk"

def post(source_ip, target):
    encoded = base64.b64encode(
        ("target_app=" + target).encode("utf-16le")
    ).decode("ascii")
    body = json.dumps({"config": encoded}).encode("utf-8")
    conn = http.client.HTTPConnection(
        SERVER, 8080, timeout=5, source_address=(source_ip, 0)
    )
    try:
        conn.request(
            "POST", "/", body=body,
            headers={"Content-Type": "application/json"}
        )
        response = conn.getresponse()
        response.read()
        return response.status
    finally:
        conn.close()

def config_contents():
    assert os.path.isfile(CONFIG), f"Config file missing: {CONFIG}"
    with open(CONFIG, "r", encoding="utf-8") as f:
        return f.read().strip()

def random_loopback():
    return "127.%d.%d.%d" % tuple(secrets.randbelow(254) + 1 for _ in range(3))

def test_random_utf16_payloads_per_ip_and_window():
    assert os.path.isfile("/home/user/server.py"), "Submitted server.py is missing"

    client_a = random_loopback()
    client_b = random_loopback()
    while client_b == client_a:
        client_b = random_loopback()

    last_target = None
    # Interleave two independently limited clients and use unpredictable,
    # non-ASCII UTF-16LE values on every request.
    for round_no in range(3):
        for label, source in (("A", client_a), ("B", client_b)):
            target = f"MobileΩ🚀_{label}_{round_no}_{secrets.token_hex(10)}"
            assert post(source, target) == 200
            assert config_contents() == f"TARGET := {target}"
            last_target = target

    blocked_a = f"BlockedA_{secrets.token_hex(10)}"
    assert post(client_a, blocked_a) == 429
    assert config_contents() == f"TARGET := {last_target}"

    blocked_b = f"BlockedB_{secrets.token_hex(10)}"
    assert post(client_b, blocked_b) == 429
    assert config_contents() == f"TARGET := {last_target}"

    # A one-minute limiter must release the client after the window expires.
    time.sleep(61.2)
    after_window = f"AfterWindowΩ_{secrets.token_hex(10)}"
    assert post(client_a, after_window) == 200
    assert config_contents() == f"TARGET := {after_window}"
TEST_EOF

    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_extended.py -x --tb=short 2>&1; then
        RESULT=0
    fi
fi

if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
fi
stop_listener SIGTERM

if [ "$RESULT" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
