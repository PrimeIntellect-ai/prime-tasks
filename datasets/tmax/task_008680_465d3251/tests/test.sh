#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import stat
import subprocess


def test_process_sh_exists_and_executable():
    script_path = "/home/user/process.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"{script_path} is not executable"


def test_process_sh_contains_flock():
    script_path = "/home/user/process.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"

    with open(script_path, "r") as f:
        content = f.read()

    assert "flock" in content, f"{script_path} does not use 'flock' as required"


def test_execute_process_script_once():
    entries = {
        "logA.cst": "LogEntryA: Start Job 123",
        "logB.cst": "LogEntryB: Processing Data...",
        "logC.cst": "LogEntryC: End Job 123",
    }

    for filename, plaintext in entries.items():
        encoded = base64.b64encode(plaintext.encode("utf-8")).decode("ascii")[::-1]
        with open(os.path.join("/home/user/project_logs", filename), "w") as f:
            f.write(encoded)

    log_path = "/home/user/project_logs/consolidated.log"
    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run(
        ["/home/user/process.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"process.sh failed with exit code {result.returncode}: {result.stderr}"


def test_consolidated_log_exists_and_content():
    log_path = "/home/user/project_logs/consolidated.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did the script run?"

    expected_lines = [
        "LogEntryA: Start Job 123",
        "LogEntryB: Processing Data...",
        "LogEntryC: End Job 123"
    ]

    with open(log_path, "r") as f:
        actual_lines = f.read().splitlines()

    assert actual_lines == expected_lines, \
        f"Contents of {log_path} do not match the expected consolidated log entries. Got: {actual_lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
