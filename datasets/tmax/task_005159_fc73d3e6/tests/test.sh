#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import requests
import pytest
import time
import uuid

API_URL = "http://127.0.0.1:9000/check_access"
LOG_FILE = "/home/user/access_audit.log"
LEDGER_FILE = "/home/user/secure_ledger.txt"
CHECKER = "/app/acl_checker"


def wait_for_service():
    for _ in range(10):
        try:
            requests.get("http://127.0.0.1:9000/")
            return
        except requests.exceptions.ConnectionError:
            pass
        try:
            requests.post(API_URL, json={})
            return
        except requests.exceptions.ConnectionError:
            pass
        time.sleep(0.5)


@pytest.fixture(scope="module", autouse=True)
def setup_and_teardown():
    wait_for_service()
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)


def test_path_traversal():
    payload = {
        "file_path": "/etc/../shadow",
        "auth_token": "test",
        "justification": "none"
    }
    response = requests.post(API_URL, json=payload)
    assert response.status_code == 403, f"Expected 403, got {response.status_code}"
    assert response.json() == {"error": "Malicious path detected"}, "Incorrect error message for path traversal"


def test_double_slash():
    payload = {
        "file_path": "/etc//shadow",
        "auth_token": "test",
        "justification": "none"
    }
    response = requests.post(API_URL, json=payload)
    assert response.status_code == 403, f"Expected 403, got {response.status_code}"
    assert response.json() == {"error": "Malicious path detected"}, "Incorrect error message for double slash"


def test_integrity_failure():
    payload = {
        "file_path": "/home/user/modified.txt",
        "auth_token": "valid",
        "justification": "none"
    }
    response = requests.post(API_URL, json=payload)
    assert response.status_code == 403, f"Expected 403, got {response.status_code}"
    assert response.json() == {"error": "Integrity check failed"}, "Incorrect error message for integrity failure"


def test_success_granted():
    payload = {
        "file_path": "/home/user/valid.txt",
        "auth_token": "sekret",
        "justification": "Check 123-45-6789."
    }
    response = requests.post(API_URL, json=payload)
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    data = response.json()
    assert data.get("access") == "GRANTED", "Access should be GRANTED"
    assert data.get("logged_justification") == "Check ***-**-****.", "Justification not correctly redacted"


def test_success_denied():
    payload = {
        "file_path": "/home/user/valid.txt",
        "auth_token": "wrong",
        "justification": "View 000-00-0000"
    }
    response = requests.post(API_URL, json=payload)
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    data = response.json()
    assert data.get("access") == "DENIED", "Access should be DENIED"
    assert data.get("logged_justification") == "View ***-**-****", "Justification not correctly redacted"


def test_audit_log():
    assert os.path.exists(LOG_FILE), "Audit log file was not created"
    with open(LOG_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    # We expect exactly 2 lines from the successful requests
    assert len(lines) >= 2, "Audit log should contain at least 2 entries for the valid requests"

    expected_granted = "[GRANTED] - File: /home/user/valid.txt - Justification: Check ***-**-****."
    expected_denied = "[DENIED] - File: /home/user/valid.txt - Justification: View ***-**-****"

    assert expected_granted in lines, f"Expected log entry '{expected_granted}' not found"
    assert expected_denied in lines, f"Expected log entry '{expected_denied}' not found"


def test_randomized_ledger_hashing_checker_invocation_and_logging():
    nonce = uuid.uuid4().hex
    valid_path = f"/home/user/audit_valid_{nonce}.txt"
    mismatch_path = f"/home/user/audit_mismatch_{nonce}.txt"
    unknown_path = f"/home/user/audit_unknown_{nonce}.txt"
    probe_path = f"/tmp/acl_probe_{nonce}.jsonl"
    backup_checker = f"/tmp/acl_checker_{nonce}.bak"
    grant_token = f"grant-{uuid.uuid4().hex}"
    deny_token = f"deny-{uuid.uuid4().hex}"
    valid_content = os.urandom(193)
    old_ledger = open(LEDGER_FILE, "rb").read()

    with open(valid_path, "wb") as f:
        f.write(valid_content)
    with open(mismatch_path, "wb") as f:
        f.write(os.urandom(127))
    with open(unknown_path, "wb") as f:
        f.write(os.urandom(89))

    valid_hash = hashlib.sha256(valid_content).hexdigest()
    mismatch_recorded_hash = hashlib.sha256(b"content that is not in the file").hexdigest()
    with open(LEDGER_FILE, "ab") as f:
        if old_ledger and not old_ledger.endswith(b"\n"):
            f.write(b"\n")
        f.write(f"{valid_hash}  {valid_path}\n".encode())
        f.write(f"{mismatch_recorded_hash}  {mismatch_path}\n".encode())

    assert os.path.isfile(CHECKER), "Legacy checker is missing"
    assert os.access(CHECKER, os.X_OK), "Legacy checker is not executable"

    os.replace(CHECKER, backup_checker)
    shim = f'''#!/usr/bin/python3
import json
import sys
with open({probe_path!r}, "a") as out:
    out.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(0 if len(sys.argv) == 3 and sys.argv[2] == {grant_token!r} else 1)
'''
    with open(CHECKER, "w") as f:
        f.write(shim)
    os.chmod(CHECKER, 0o755)

    def probe_calls():
        if not os.path.exists(probe_path):
            return []
        with open(probe_path) as f:
            return [json.loads(line) for line in f if line.strip()]

    try:
        # Rejected requests must not reach the legacy checker.
        malicious_path = f"/home/user/../audit_valid_{nonce}.txt"
        response = requests.post(API_URL, json={
            "file_path": malicious_path,
            "auth_token": grant_token,
            "justification": "random"
        })
        assert response.status_code == 403
        assert response.json() == {"error": "Malicious path detected"}

        for bad_path in (mismatch_path, unknown_path):
            response = requests.post(API_URL, json={
                "file_path": bad_path,
                "auth_token": grant_token,
                "justification": "random"
            })
            assert response.status_code == 403
            assert response.json() == {"error": "Integrity check failed"}
        assert probe_calls() == [], "Checker was invoked before path and integrity validation"

        grant_justification = f"Case {nonce}: 314-15-9265 and 271-82-8182"
        grant_redacted = re.sub(r"\d{3}-\d{2}-\d{4}", "***-**-****", grant_justification)
        response = requests.post(API_URL, json={
            "file_path": valid_path,
            "auth_token": grant_token,
            "justification": grant_justification
        })
        assert response.status_code == 200
        assert response.json() == {
            "access": "GRANTED",
            "logged_justification": grant_redacted
        }

        deny_justification = f"No SSN here {nonce}"
        response = requests.post(API_URL, json={
            "file_path": valid_path,
            "auth_token": deny_token,
            "justification": deny_justification
        })
        assert response.status_code == 200
        assert response.json() == {
            "access": "DENIED",
            "logged_justification": deny_justification
        }

        expected_calls = [[valid_path, grant_token], [valid_path, deny_token]]
        assert probe_calls() == expected_calls, "Wrapper did not invoke /app/acl_checker with the required arguments"

        with open(LOG_FILE) as f:
            lines = [line.rstrip("\n") for line in f]
        assert f"[GRANTED] - File: {valid_path} - Justification: {grant_redacted}" in lines
        assert f"[DENIED] - File: {valid_path} - Justification: {deny_justification}" in lines

        # The hash must be recomputed, rather than merely trusting ledger membership.
        with open(valid_path, "ab") as f:
            f.write(b"tampered-after-success")
        response = requests.post(API_URL, json={
            "file_path": valid_path,
            "auth_token": grant_token,
            "justification": "after mutation"
        })
        assert response.status_code == 403
        assert response.json() == {"error": "Integrity check failed"}
        assert probe_calls() == expected_calls, "Checker was invoked for a file whose hash no longer matched"
    finally:
        if os.path.exists(CHECKER):
            os.remove(CHECKER)
        os.replace(backup_checker, CHECKER)
        with open(LEDGER_FILE, "wb") as f:
            f.write(old_ledger)
        for path in (valid_path, mismatch_path, unknown_path, probe_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
