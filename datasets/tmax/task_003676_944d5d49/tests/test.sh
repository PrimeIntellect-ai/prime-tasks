#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import random
import subprocess
import pytest

def test_leak_frame_count():
    count_file = "/home/user/leak_frame_count.txt"
    assert os.path.exists(count_file), f"File {count_file} does not exist."
    assert os.path.isfile(count_file), f"{count_file} is not a file."

    with open(count_file, "r") as f:
        content = f.read()

    assert content == "47\n", f"Expected file content to be exactly '47\\n', but got {repr(content)}"

def test_secure_audit_logs_dir():
    dir_path = "/home/user/secure_audit_logs"
    # Ensure it exists and is a directory
    assert os.path.exists(dir_path), f"Directory {dir_path} does not exist."
    assert os.path.isdir(dir_path), f"{dir_path} is not a directory."

    # Check permissions
    st = os.stat(dir_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o700, f"Expected permissions 700 (octal), but got {oct(permissions)}"

def test_sanitize_audit_exists_and_executable():
    agent_path = "/home/user/sanitize_audit"
    assert os.path.exists(agent_path), f"Executable {agent_path} does not exist."
    assert os.path.isfile(agent_path), f"{agent_path} is not a file."
    assert os.access(agent_path, os.X_OK), f"File {agent_path} does not have executable permissions."

def test_sanitize_audit_fuzz_equivalence():
    agent_path = "/home/user/sanitize_audit"
    oracle_path = "/tests/reference_sanitize_audit"

    assert os.path.exists(oracle_path), f"Oracle {oracle_path} does not exist."

    # Generate fuzz inputs
    random.seed(42)
    charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_=;<>/"
    patterns = ["--db-pass=secret_val", "--db-pass=123 ", "<script>", "; rm -rf /"]
    N = 5000

    inputs = []
    for _ in range(N):
        length = random.randint(10, 250)
        base = "".join(random.choices(charset, k=length))

        # Randomly inject patterns to ensure edge cases are hit
        if random.random() < 0.6:
            pat = random.choice(patterns)
            insert_pos = random.randint(0, len(base))
            base = base[:insert_pos] + pat + base[insert_pos:]

        # The prompt specifies the program reads one line of text.
        # We append a newline to simulate typical stdin reading.
        inputs.append(base + "\n")

    for i, test_input in enumerate(inputs):
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path],
            input=test_input,
            capture_output=True,
            text=True
        )
        oracle_output = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [agent_path],
            input=test_input,
            capture_output=True,
            text=True
        )
        agent_output = agent_proc.stdout

        assert agent_output == oracle_output, (
            f"Fuzz equivalence failed on input #{i}.\n"
            f"Input: {repr(test_input)}\n"
            f"Expected (Oracle): {repr(oracle_output)}\n"
            f"Got (Agent): {repr(agent_output)}\n"
            f"Agent stderr: {repr(agent_proc.stderr)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
