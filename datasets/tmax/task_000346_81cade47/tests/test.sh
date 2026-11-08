#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import hashlib
import secrets
import subprocess

PENTEST_DIR = "/home/user/pentest"
AUTH_FILE = os.path.join(PENTEST_DIR, "auth_capture.txt")
SERVER_BIN = os.path.join(PENTEST_DIR, "server.bin")
SERVER_CRT = os.path.join(PENTEST_DIR, "server.crt")
ANALYZE_FILE = os.path.join(PENTEST_DIR, "analyze.py")
REPORT_FILE = os.path.join(PENTEST_DIR, "report.txt")


def get_expected_values():
    # 1. Extract client_id and file_hash from auth_capture.txt
    client_id = None
    expected_file_hash = None
    with open(AUTH_FILE, "r") as f:
        for line in f:
            if line.startswith("Authorization: Bearer "):
                token_b64 = line.strip().split(" ")[2]
                token_json = base64.b64decode(token_b64).decode("utf-8")
                token_data = json.loads(token_json)
                client_id = token_data.get("client_id")
                expected_file_hash = token_data.get("file_hash")
                break

    # 2. Compute SHA-256 of server.bin
    hasher = hashlib.sha256()
    with open(SERVER_BIN, "rb") as f:
        hasher.update(f.read())
    actual_file_hash = hasher.hexdigest()
    integrity = "Valid" if actual_file_hash == expected_file_hash else "Invalid"

    # 3. Extract Issuer CN from server.crt using openssl
    result = subprocess.run(
        ["openssl", "x509", "-in", SERVER_CRT, "-noout", "-issuer"],
        capture_output=True,
        text=True,
        check=True,
    )
    issuer_line = result.stdout.strip()
    issuer_cn = None
    if "CN = " in issuer_line:
        issuer_cn = issuer_line.split("CN = ")[1].split(",")[0].strip()
    elif "CN=" in issuer_line:
        issuer_cn = issuer_line.split("CN=")[1].split("/")[0].strip()

    return client_id, integrity, issuer_cn


def run_analysis():
    if os.path.exists(REPORT_FILE):
        os.remove(REPORT_FILE)
    result = subprocess.run(
        ["python3", ANALYZE_FILE],
        cwd=PENTEST_DIR,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"analyze.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def assert_report(expected_client_id, expected_integrity, expected_issuer_cn):
    assert os.path.isfile(REPORT_FILE), (
        f"Report file {REPORT_FILE} does not exist. Ensure your script writes to this exact path."
    )

    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 3, f"Expected at least 3 lines in {REPORT_FILE}, found {len(lines)}."
    assert lines[0] == f"Client ID: {expected_client_id}", (
        f"Line 1 is incorrect. Expected 'Client ID: {expected_client_id}', got '{lines[0]}'"
    )
    assert lines[1] == f"Integrity: {expected_integrity}", (
        f"Line 2 is incorrect. Expected 'Integrity: {expected_integrity}', got '{lines[1]}'"
    )
    assert lines[2] == f"Certificate Issuer CN: {expected_issuer_cn}", (
        f"Line 3 is incorrect. Expected 'Certificate Issuer CN: {expected_issuer_cn}', got '{lines[2]}'"
    )


def write_auth(client_id, file_hash):
    payload = json.dumps({"client_id": client_id, "file_hash": file_hash}).encode("utf-8")
    token = base64.b64encode(payload).decode("ascii")
    with open(AUTH_FILE, "w") as f:
        f.write("GET /api/v1/secure/download HTTP/1.1\n")
        f.write("Host: vulnerable.local\n")
        f.write(f"Authorization: Bearer {token}\n")
        f.write("Accept: */*\n")


def test_report_exists_and_correct():
    assert os.path.isfile(ANALYZE_FILE), f"Required Python script {ANALYZE_FILE} does not exist."
    with open(ANALYZE_FILE, "rb") as f:
        source = f.read()
    compile(source, ANALYZE_FILE, "exec")

    with open(AUTH_FILE, "rb") as f:
        original_auth = f.read()
    with open(SERVER_BIN, "rb") as f:
        original_bin = f.read()

    original_expected = get_expected_values()
    issuer_cn = original_expected[2]

    try:
        # Preserve the original verifier's exact report assertions, but generate
        # the report by actually executing the required script.
        run_analysis()
        assert_report(*original_expected)

        # Exercise the script with unpredictable fixtures so a prewritten report
        # or a script containing only the fixed answers cannot pass.
        valid_data = secrets.token_bytes(73)
        valid_client = "client-" + secrets.token_hex(12)
        valid_hash = hashlib.sha256(valid_data).hexdigest()
        with open(SERVER_BIN, "wb") as f:
            f.write(valid_data)
        write_auth(valid_client, valid_hash)
        run_analysis()
        assert_report(valid_client, "Valid", issuer_cn)

        invalid_data = secrets.token_bytes(91)
        invalid_client = "client-" + secrets.token_hex(12)
        actual_hash = hashlib.sha256(invalid_data).hexdigest()
        wrong_hash = secrets.token_hex(32)
        while wrong_hash == actual_hash:
            wrong_hash = secrets.token_hex(32)
        with open(SERVER_BIN, "wb") as f:
            f.write(invalid_data)
        write_auth(invalid_client, wrong_hash)
        run_analysis()
        assert_report(invalid_client, "Invalid", issuer_cn)
    finally:
        with open(AUTH_FILE, "wb") as f:
            f.write(original_auth)
        with open(SERVER_BIN, "wb") as f:
            f.write(original_bin)

    # Leave the requested report generated from the original intercepted files.
    run_analysis()
    assert_report(*original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
