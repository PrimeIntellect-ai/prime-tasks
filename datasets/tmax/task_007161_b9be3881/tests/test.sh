#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import re
import subprocess
import uuid
import pytest

SECURE_LOGS_DIR = '/home/user/secure_logs'
NEW_LOG_FILE = '/home/user/secure_logs/error_summary.log'
ROTATED_LOG_FILE = '/home/user/secure_logs/error_summary.log.1'
RAW_LOG_FILE = '/home/user/raw_logs/payment.log'
PROCESS_SCRIPT = '/home/user/process_logs.py'
ROTATE_SCRIPT = '/home/user/rotate_logs.sh'

def test_secure_logs_directory_permissions():
    assert os.path.exists(SECURE_LOGS_DIR), f"Directory {SECURE_LOGS_DIR} does not exist."
    mode = os.stat(SECURE_LOGS_DIR).st_mode
    perms = stat.S_IMODE(mode)
    assert perms == 0o700, f"Expected {SECURE_LOGS_DIR} to have permissions 0700, but got {oct(perms)}"

def test_rotated_log_file_permissions():
    assert os.path.exists(ROTATED_LOG_FILE), f"File {ROTATED_LOG_FILE} does not exist. Did the rotation script run?"
    mode = os.stat(ROTATED_LOG_FILE).st_mode
    perms = stat.S_IMODE(mode)
    assert perms == 0o400, f"Expected {ROTATED_LOG_FILE} to have permissions 0400, but got {oct(perms)}"

def test_new_log_file_permissions():
    assert os.path.exists(NEW_LOG_FILE), f"File {NEW_LOG_FILE} does not exist. Did the rotation script run?"
    mode = os.stat(NEW_LOG_FILE).st_mode
    perms = stat.S_IMODE(mode)
    assert perms == 0o400, f"Expected {NEW_LOG_FILE} to have permissions 0400, but got {oct(perms)}"

def test_new_log_file_is_empty():
    assert os.path.exists(NEW_LOG_FILE), f"File {NEW_LOG_FILE} does not exist."
    with open(NEW_LOG_FILE, 'r') as f:
        content = f.read()
    assert content == "", f"Expected {NEW_LOG_FILE} to be empty, but it contains data."

def test_rotated_log_file_content():
    assert os.path.exists(RAW_LOG_FILE), f"Raw log file {RAW_LOG_FILE} is missing."
    assert os.path.exists(ROTATED_LOG_FILE), f"Rotated log file {ROTATED_LOG_FILE} is missing."

    expected_lines = []
    with open(RAW_LOG_FILE, 'r') as f:
        for line in f:
            if "[ERROR]" in line and 'action="checkout"' in line:
                tx_id_match = re.search(r'tx_id="([^"]+)"', line)
                reason_match = re.search(r'reason="([^"]+)"', line)
                if tx_id_match and reason_match:
                    tx_id = tx_id_match.group(1)
                    reason = reason_match.group(1)
                    expected_lines.append(f"TX_ID: {tx_id} | REASON: {reason}")

    expected_content = "\n".join(expected_lines).strip()

    with open(ROTATED_LOG_FILE, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {ROTATED_LOG_FILE} does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )

def test_scripts_exist_and_work_on_fresh_input():
    for script_path in (PROCESS_SCRIPT, ROTATE_SCRIPT):
        assert os.path.exists(script_path), f"Required script {script_path} does not exist."
        assert stat.S_ISREG(os.lstat(script_path).st_mode), f"{script_path} must be a regular file."

    token = uuid.uuid4().hex
    tx_ids = [f"TX-{token[:8]}", f"TX-{token[8:16]}", f"TX-{token[16:24]}"]
    reasons = [f"declined_{token[24:28]}", f"network_{token[28:32]}", f"limit_{token[:4]}"]
    raw_lines = [
        f'2026-01-01T00:00:00 [INFO] action="checkout" tx_id="IGNORE-{token[:6]}" reason="ignored"',
        f'2026-01-01T00:00:01 [ERROR] action="checkout" tx_id="{tx_ids[0]}" reason="{reasons[0]}"',
        f'2026-01-01T00:00:02 [ERROR] action="refund" tx_id="IGNORE-{token[6:12]}" reason="ignored"',
        f'2026-01-01T00:00:03 [ERROR] action="checkout" tx_id="{tx_ids[1]}" reason="{reasons[1]}" module="gateway"',
        f'2026-01-01T00:00:04 [WARN] action="checkout" tx_id="IGNORE-{token[12:18]}" reason="ignored"',
        f'2026-01-01T00:00:05 [ERROR] action="checkout" tx_id="{tx_ids[2]}" reason="{reasons[2]}"',
    ]
    expected = "\n".join(
        f"TX_ID: {tx_id} | REASON: {reason}"
        for tx_id, reason in zip(tx_ids, reasons)
    )

    with open(RAW_LOG_FILE, 'w') as f:
        f.write("\n".join(raw_lines) + "\n")

    os.makedirs(SECURE_LOGS_DIR, exist_ok=True)
    os.chmod(SECURE_LOGS_DIR, 0o700)
    for path in (NEW_LOG_FILE, ROTATED_LOG_FILE):
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(
        ['python3', PROCESS_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{PROCESS_SCRIPT} failed on fresh input with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(NEW_LOG_FILE), f"{PROCESS_SCRIPT} did not create {NEW_LOG_FILE}."
    with open(NEW_LOG_FILE, 'r') as f:
        processed_content = f.read().strip()
    assert processed_content == expected, (
        f"{PROCESS_SCRIPT} produced incorrect output for fresh input.\n"
        f"Expected:\n{expected}\nActual:\n{processed_content}"
    )

    os.chmod(NEW_LOG_FILE, 0o400)
    result = subprocess.run(
        ['bash', ROTATE_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{ROTATE_SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(ROTATED_LOG_FILE), f"{ROTATE_SCRIPT} did not create the rotated log."
    assert os.path.isfile(NEW_LOG_FILE), f"{ROTATE_SCRIPT} did not create the new log."
    with open(ROTATED_LOG_FILE, 'r') as f:
        rotated_content = f.read().strip()
    with open(NEW_LOG_FILE, 'r') as f:
        new_content = f.read()
    assert rotated_content == expected, "The rotation script did not preserve the generated summary."
    assert new_content == "", "The rotation script did not create an empty new log."
    assert stat.S_IMODE(os.stat(ROTATED_LOG_FILE).st_mode) == 0o400
    assert stat.S_IMODE(os.stat(NEW_LOG_FILE).st_mode) == 0o400
    assert stat.S_IMODE(os.stat(SECURE_LOGS_DIR).st_mode) == 0o700
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    mkdir -p /logs/verifier
    echo "1" > /logs/verifier/reward.txt
else
    mkdir -p /logs/verifier
    echo "0" > /logs/verifier/reward.txt
fi
