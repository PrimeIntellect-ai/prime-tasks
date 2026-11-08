#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import re
import urllib.error
import urllib.request

import pytest

APP_PATH = "/home/user/app.py"
MANIFEST_PATH = "/home/user/manifest.txt"
INTEGRITY_LOG_PATH = "/home/user/integrity.log"
REDACTED_REPORTS_PATH = "/home/user/redacted_reports.json"
PORT = 8080


def listening_socket_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    if int(local_address.rsplit(":", 1)[1], 16) == port:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def find_app_server_pids():
    socket_inodes = listening_socket_inodes(PORT)
    assert socket_inodes, f"No process is listening on port {PORT}."

    matches = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        proc_dir = f"/proc/{entry}"
        try:
            with open(f"{proc_dir}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            if APP_PATH not in argv:
                continue

            owned = set()
            for fd in os.listdir(f"{proc_dir}/fd"):
                try:
                    target = os.readlink(f"{proc_dir}/fd/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match:
                    owned.add(match.group(1))

            if owned & socket_inodes:
                matches.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    assert matches, f"Port {PORT} is not being served by python3 {APP_PATH}."
    return matches


def base64url(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def fetch_reports_with_forged_token():
    header = {"alg": "none", "typ": "JWT"}
    payload = {"user": "admin", "role": "admin"}
    token = f"{base64url(header)}.{base64url(payload)}."
    request = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/api/reports",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        pytest.fail(f"Forged alg=none admin token was rejected with HTTP {exc.code}.")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        pytest.fail(f"Could not retrieve valid JSON from /api/reports: {exc}")


def redact_ssns(value):
    if isinstance(value, dict):
        return {key: redact_ssns(item) for key, item in value.items()}
    if isinstance(value, list):
        return [redact_ssns(item) for item in value]
    if isinstance(value, str):
        return re.sub(r"\d{3}-\d{2}-\d{4}", "[REDACTED]", value)
    return value


def test_integrity_log():
    assert os.path.exists(INTEGRITY_LOG_PATH), f"{INTEGRITY_LOG_PATH} does not exist."
    with open(INTEGRITY_LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "VALID", f"Expected 'VALID' in {INTEGRITY_LOG_PATH}, but found '{content}'."

    with open(MANIFEST_PATH, "r") as f:
        expected_hash = f.read().strip().split()[0]
    with open(APP_PATH, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()
    assert actual_hash == expected_hash, "app.py does not match the SHA-256 hash in manifest.txt."


def test_redacted_reports():
    assert os.path.exists(REDACTED_REPORTS_PATH), f"{REDACTED_REPORTS_PATH} does not exist."
    find_app_server_pids()

    with open(REDACTED_REPORTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REDACTED_REPORTS_PATH} does not contain valid JSON.")

    expected_data = {
        "reports": [
            {"id": 1, "data": "Routine server maintenance completed.", "author": "alice"},
            {"id": 2, "data": "User [REDACTED] reported a billing error.", "author": "bob"},
            {"id": 3, "data": "Contractor [REDACTED] requires access to db-prod.", "author": "charlie"},
        ]
    }
    assert data == expected_data, "The redacted reports JSON does not match the expected structure and content."

    live_reports = fetch_reports_with_forged_token()
    dynamically_expected = redact_ssns(live_reports)
    assert data == dynamically_expected, \
        "redacted_reports.json does not match the live /api/reports response after SSN redaction."


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
