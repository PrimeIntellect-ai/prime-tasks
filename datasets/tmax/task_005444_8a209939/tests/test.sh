#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/system_scripts/process_data.sh"
EXPECTED_SCRIPT = b'''#!/bin/bash
# Data processor
INPUT_FILE="/home/user/input.dat"
if [ -f "$INPUT_FILE" ]; then
    ENCODED_DATA=$(cat "$INPUT_FILE")
    DECODED_DATA=$(echo "$ENCODED_DATA" | base64 -d)
    # Unsafe execution of decoded data
    eval "$DECODED_DATA"
else
    echo "No input file found."
fi
'''

def test_vuln_path():
    path = "/home/user/vuln_path.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == SCRIPT_PATH, f"Incorrect content in {path}. Expected '{SCRIPT_PATH}'."


def test_vulnerable_script_unchanged_and_world_writable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert os.stat(SCRIPT_PATH).st_mode & stat.S_IWOTH, f"{SCRIPT_PATH} is not world-writable."
    with open(SCRIPT_PATH, "rb") as f:
        content = f.read()
    assert content == EXPECTED_SCRIPT, f"The original vulnerable script {SCRIPT_PATH} was modified."


def test_audit_evidence():
    path = "/home/user/audit_evidence.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == "AUDIT_COMPLETE", f"Incorrect content in {path}. Expected 'AUDIT_COMPLETE'."


def test_used_payload():
    path = "/home/user/used_payload.txt"
    input_path = "/home/user/input.dat"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.exists(input_path), f"File {input_path} does not exist."

    with open(path, "rb") as f:
        payload_bytes = f.read()
    with open(input_path, "rb") as f:
        input_bytes = f.read()
    assert input_bytes == payload_bytes, f"{input_path} does not exactly match {path}."

    content = payload_bytes.decode("utf-8").strip()
    try:
        decoded_bytes = base64.b64decode(content)
        decoded = decoded_bytes.decode('utf-8')
    except Exception as e:
        pytest.fail(f"Failed to decode base64 from {path}: {e}")

    assert "AUDIT_COMPLETE" in decoded, f"The decoded payload does not contain 'AUDIT_COMPLETE'. Payload was: {decoded}"
    assert "/home/user/audit_evidence.txt" in decoded, f"The decoded payload does not contain the target file path. Payload was: {decoded}"

    evidence_path = "/home/user/audit_evidence.txt"
    os.unlink(evidence_path)
    result = subprocess.run(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}. "
        f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(evidence_path), f"Executing {SCRIPT_PATH} did not create {evidence_path}."
    with open(evidence_path, "rb") as f:
        evidence = f.read()
    assert evidence == b"AUDIT_COMPLETE", (
        f"Executing {SCRIPT_PATH} did not write exactly 'AUDIT_COMPLETE' to {evidence_path}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
