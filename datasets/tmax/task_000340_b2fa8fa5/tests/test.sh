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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import atexit
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import time

import pytest
import requests

API_URL = "http://127.0.0.1:9090/api/scan"
SCANNER = "/app/legacy_scanner"
BACKUP = f"/tmp/legacy_scanner.backup.{os.getpid()}"
MARKER = f"/tmp/legacy_scanner.calls.{secrets.token_hex(8)}"
TIMEOUT_PID = f"/tmp/legacy_scanner.timeout.{secrets.token_hex(8)}"
NONCE = secrets.token_hex(24)
DYNAMIC_PORT, TIMEOUT_PORT, FAILURE_PORT = map(str, random.sample(range(41000, 60000), 3))
_installed = False


def post(payload, timeout=7):
    try:
        return requests.post(API_URL, json=payload, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API: {exc}")


def assert_json_response(response):
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/json"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")


def listener_pid():
    wanted = "0100007F:2382"  # 127.0.0.1:9090
    inode = None
    with open("/proc/net/tcp", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            if fields[1].upper() == wanted and fields[3] == "0A":
                inode = fields[9]
                break
    assert inode is not None, "No listener is bound specifically to 127.0.0.1:9090"

    socket_name = f"socket:[{inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == socket_name:
                        return int(entry)
                except OSError:
                    pass
        except OSError:
            pass
    pytest.fail("Could not identify the process owning the API listener")


def restore_scanner():
    global _installed
    if _installed and os.path.exists(BACKUP):
        os.replace(BACKUP, SCANNER)
        _installed = False


atexit.register(restore_scanner)


def install_instrumented_scanner():
    global _installed
    assert not _installed
    shutil.copy2(SCANNER, BACKUP)
    script = f'''#!/usr/bin/python3
import json
import os
import sys
import time

ip = sys.argv[1] if len(sys.argv) > 1 else ""
port = sys.argv[2] if len(sys.argv) > 2 else ""
with open({MARKER!r}, "a", encoding="utf-8") as marker:
    marker.write(json.dumps([ip, port]) + "\\n")

if port == {TIMEOUT_PORT!r}:
    with open({TIMEOUT_PID!r}, "w", encoding="ascii") as handle:
        handle.write(str(os.getpid()))
    time.sleep(8)
    result = {{"should_not": "complete"}}
elif port == {FAILURE_PORT!r}:
    sys.exit(17)
else:
    result = {{
        "service": "dynamic-service",
        "nonce": {NONCE!r},
        "target": {{"ip": ip, "port": port}},
        "nested": {{
            "password": "dynamic-password",
            "items": [
                {{"api_token": "dynamic-token", "ordinary": "preserved"}},
                {{"secret": {{"must": "all disappear"}}}}
            ],
            "Secret": "case-sensitive-preserved"
        }},
        "password_hint": "not-sensitive-by-exact-match"
    }}

plaintext = json.dumps(result, separators=(",", ":")).encode()
sys.stdout.write("".join(f"{{byte ^ 0x42:02X}}" for byte in plaintext) + "\\n")
'''
    temporary = SCANNER + ".verifier-new"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(script)
    os.chmod(temporary, 0o755)
    os.replace(temporary, SCANNER)
    _installed = True


def marker_calls():
    with open(MARKER, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def test_service_is_running_and_is_go():
    try:
        requests.options(API_URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("The Go web service is not running on 127.0.0.1:9090")

    pid = listener_pid()
    result = subprocess.run(
        ["go", "version", "-m", f"/proc/{pid}/exe"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=3,
    )
    assert result.returncode == 0 and "go1." in result.stdout, (
        f"The process listening on port 9090 is not a Go executable: {result.stdout}"
    )


def test_scan_port_8080():
    payload = {"target_ip": "10.0.0.5", "target_port": "8080"}
    data = assert_json_response(post(payload, timeout=5))
    assert data.get("service") == "http", "Expected 'service' to be 'http'"
    assert data.get("status") == "vulnerable", "Expected 'status' to be 'vulnerable'"
    assert data.get("details") == "exposed admin panel", "Expected expected details"
    assert "api_token" in data, "The 'api_token' key is missing from the response"
    assert data["api_token"] == "[REDACTED]"


def test_scan_port_3306():
    payload = {"target_ip": "10.0.0.5", "target_port": "3306"}
    data = assert_json_response(post(payload, timeout=5))
    assert data.get("service") == "mysql", "Expected 'service' to be 'mysql'"
    assert data.get("vulnerability") == "empty root password"
    assert "password" in data, "The 'password' key is missing from the response"
    assert data["password"] == "[REDACTED]"


def test_dynamic_scanner_execution_decryption_and_recursive_redaction():
    install_instrumented_scanner()
    target_ip = f"198.51.100.{random.randint(1, 250)}"
    payload = {"target_ip": target_ip, "target_port": DYNAMIC_PORT}
    data = assert_json_response(post(payload))

    assert [target_ip, DYNAMIC_PORT] in marker_calls(), (
        "The wrapper did not execute /app/legacy_scanner with the supplied arguments"
    )
    assert data["service"] == "dynamic-service"
    assert data["nonce"] == NONCE
    assert data["target"] == {"ip": target_ip, "port": DYNAMIC_PORT}
    assert data["nested"]["password"] == "[REDACTED]"
    assert data["nested"]["items"][0] == {
        "api_token": "[REDACTED]",
        "ordinary": "preserved",
    }
    assert data["nested"]["items"][1]["secret"] == "[REDACTED]"
    assert data["nested"]["Secret"] == "case-sensitive-preserved"
    assert data["password_hint"] == "not-sensitive-by-exact-match"


def test_scanner_failure_returns_500():
    response = post({"target_ip": "203.0.113.7", "target_port": FAILURE_PORT})
    assert ["203.0.113.7", FAILURE_PORT] in marker_calls()
    assert response.status_code == 500, (
        f"Expected HTTP 500 when scanner exits unsuccessfully, got {response.status_code}"
    )


def test_five_second_timeout_and_process_termination():
    started = time.monotonic()
    response = post({"target_ip": "203.0.113.8", "target_port": TIMEOUT_PORT}, timeout=7)
    elapsed = time.monotonic() - started
    assert response.status_code == 500, (
        f"Expected HTTP 500 on scanner timeout, got {response.status_code}"
    )
    assert 4.0 <= elapsed <= 6.8, f"Scanner timeout was not approximately five seconds ({elapsed:.2f}s)"
    assert ["203.0.113.8", TIMEOUT_PORT] in marker_calls()

    time.sleep(0.4)
    assert os.path.exists(TIMEOUT_PID), "Instrumented scanner did not enter its timeout path"
    with open(TIMEOUT_PID, encoding="ascii") as handle:
        pid = int(handle.read())
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pass
    else:
        pytest.fail("Timed-out legacy_scanner process was left running")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
