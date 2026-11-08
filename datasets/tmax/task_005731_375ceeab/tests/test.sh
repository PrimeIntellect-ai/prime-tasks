#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import hashlib
import subprocess
import pytest

def get_last_successful_deployment(log_path):
    if not os.path.exists(log_path):
        return {}

    with open(log_path, 'r') as f:
        content = f.read()

    records = re.findall(r'\[DEPLOY_START\](.*?)\[DEPLOY_END\]', content, re.DOTALL)

    last_success_files = {}
    for record in records:
        if 'Status: SUCCESS' in record:
            last_success_files = {}
            lines = record.strip().split('\n')
            for line in lines:
                match = re.match(r'\s*-\s*(/\S+)\s*\(sha256:\s*([^\s)]+)\s*\)\s*$', line)
                if match:
                    filepath, filehash = match.groups()
                    last_success_files[filepath] = filehash

    return last_success_files

def get_current_files(directory):
    current_files = {}
    if not os.path.exists(directory):
        return current_files

    for filename in os.listdir(directory):
        if filename.endswith('.yaml') or filename.endswith('.conf'):
            filepath = os.path.join(directory, filename)
            if os.path.isfile(filepath):
                with open(filepath, 'rb') as f:
                    filehash = hashlib.sha256(f.read()).hexdigest()
                current_files[filepath] = filehash
    return current_files

def test_pending_changes_report():
    script_path = "/home/user/tracker.sh"
    report_path = "/home/user/pending_changes.txt"

    assert os.path.isfile(script_path), f"The Bash script {script_path} was not found."

    if os.path.exists(report_path):
        os.remove(report_path)

    result = subprocess.run(
        ["bash", script_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Executing {script_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(script_path), f"The Bash script {script_path} was removed during execution."
    assert os.path.isfile(report_path), f"The report file {report_path} was not found."

    log_path = "/home/user/deploy.log"
    config_dir = "/home/user/app_config"

    last_success = get_last_successful_deployment(log_path)
    current_files = get_current_files(config_dir)

    expected_entries = []

    # Check for NEW and MODIFIED
    for filepath, current_hash in current_files.items():
        if filepath not in last_success:
            expected_entries.append((filepath, f"NEW: {filepath} (sha256: {current_hash})"))
        elif last_success[filepath] != current_hash:
            expected_entries.append((filepath, f"MODIFIED: {filepath} (sha256: {current_hash})"))

    # Check for DELETED
    for filepath in last_success:
        if filepath not in current_files:
            expected_entries.append((filepath, f"DELETED: {filepath}"))

    expected_entries.sort(key=lambda entry: entry[0])
    expected_lines = [line for _, line in expected_entries]
    expected_content = "\n".join(expected_lines) + "\n" if expected_lines else ""

    with open(report_path, 'r') as f:
        actual_content = f.read()

    # Standardize line endings for comparison
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines_clean = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines_clean, (
        f"The contents of {report_path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines_clean)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
