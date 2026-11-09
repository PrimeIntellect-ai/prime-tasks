#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

GATEWAY_BIN = "/home/user/upload_gateway"
AUDIT_LOG = "/home/user/audit.log"
UPLOADS_DIR = "/home/user/uploads"

def test_gateway_executable_exists():
    """Verify that the upload_gateway executable is compiled and accessible."""
    assert os.path.isfile(GATEWAY_BIN), f"Executable {GATEWAY_BIN} not found. Did you compile it?"
    assert os.access(GATEWAY_BIN, os.X_OK), f"{GATEWAY_BIN} is not executable."

def test_gateway_behavior_and_logs():
    """Run the gateway with various inputs and verify exit codes, file creation, and logs."""
    # Clear the audit log and any previous test files to ensure a clean state
    with open(AUDIT_LOG, "w") as f:
        f.write("")

    test_file_path = os.path.join(UPLOADS_DIR, "test.txt")
    if os.path.exists(test_file_path):
        os.remove(test_file_path)

    # 1. Valid Upload
    cmd1 = [GATEWAY_BIN, "admin:1700000000:F1", "746573742e747874", "48656c6c6f576f726c64"]
    res1 = subprocess.run(cmd1, capture_output=True)
    assert res1.returncode == 0, f"Valid upload failed with exit code {res1.returncode}"

    assert os.path.isfile(test_file_path), "File test.txt was not created in the uploads directory."
    with open(test_file_path, "r") as f:
        assert f.read() == "HelloWorld", "Decoded file content mismatch for test.txt."

    # 2. Invalid Token
    cmd2 = [GATEWAY_BIN, "admin:1700000000:FA", "746573742e747874", "48656c6c6f576f726c64"]
    res2 = subprocess.run(cmd2, capture_output=True)
    assert res2.returncode == 1, f"Invalid token should exit with code 1, got {res2.returncode}"

    # 3. Path Traversal Attempt
    cmd3 = [GATEWAY_BIN, "dev:999:EA", "2e2e2f6574632f706173737764", "626164"]
    res3 = subprocess.run(cmd3, capture_output=True)
    assert res3.returncode == 3, f"Path traversal attempt should exit with code 3, got {res3.returncode}"

    bad_file_path = os.path.join(UPLOADS_DIR, "../etc/passwd")
    if os.path.exists(bad_file_path):
        os.remove(bad_file_path)
        pytest.fail("Path traversal vulnerability exists: file was written outside the intended uploads directory.")

    # 4. Invalid Hex
    cmd4 = [GATEWAY_BIN, "dev:999:EA", "746573742e74787", "48656c6c6f576f726c64"]
    res4 = subprocess.run(cmd4, capture_output=True)
    assert res4.returncode == 2, f"Invalid hex input should exit with code 2, got {res4.returncode}"

    # Verify Audit Log Exact Contents
    assert os.path.isfile(AUDIT_LOG), "Audit log file is missing."
    with open(AUDIT_LOG, "r") as f:
        log_contents = f.read()

    expected_logs = (
        "[SUCCESS] File test.txt saved for user: admin\n"
        "[AUTH_FAIL] Invalid token for user: admin\n"
        "[POLICY_FAIL] Path traversal attempt by user: dev\n"
        "[DECODE_FAIL] Invalid hex input\n"
    )

    assert log_contents == expected_logs, "Audit log contents do not perfectly match the expected sequence and formatting."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
