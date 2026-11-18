#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import tarfile
import pytest

def test_backup_exists_and_valid():
    backup_path = "/home/user/miniping_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            members = tar.getnames()
            assert any("miniping-1.2/main.c" in m for m in members) or any("main.c" in m for m in members), "Backup does not contain the expected source files."
    except tarfile.ReadError:
        pytest.fail(f"Backup file {backup_path} is not a valid gzip-compressed tarball.")

def test_binary_compiled():
    binary_path = "/app/miniping-1.2/miniping"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable."

def test_expect_script_exists():
    script_path = "/home/user/setup_miniping.exp"
    assert os.path.isfile(script_path), f"Expect script {script_path} is missing."
    assert os.access(script_path, os.X_OK) or os.path.exists(script_path), f"Expect script {script_path} not found."

def test_wrapper_script_exists_and_executable():
    script_path = "/home/user/run_uptime_check.sh"
    assert os.path.isfile(script_path), f"Wrapper script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Wrapper script {script_path} is not executable."

def test_fuzz_equivalence():
    oracle_path = "/tests/miniping_oracle"
    agent_script = "/home/user/run_uptime_check.sh"

    assert os.path.isfile(oracle_path), f"Oracle binary {oracle_path} is missing."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."

    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation

    for i in range(500):
        length = random.randint(10, 256)
        payload = "".join(random.choices(charset, k=length))

        oracle_res = subprocess.run([oracle_path, "--check", payload], capture_output=True, text=True)
        agent_res = subprocess.run([agent_script, payload], capture_output=True, text=True)

        assert agent_res.returncode == oracle_res.returncode, f"Return code mismatch on input {payload!r}: expected {oracle_res.returncode}, got {agent_res.returncode}"
        assert agent_res.stdout == oracle_res.stdout, f"Stdout mismatch on input {payload!r}:\nExpected:\n{oracle_res.stdout}\nGot:\n{agent_res.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
