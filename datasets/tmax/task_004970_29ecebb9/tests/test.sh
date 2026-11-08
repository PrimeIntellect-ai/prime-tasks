#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import tempfile
import filecmp
import pytest

AGENT_SCRIPT = "/home/user/pack_project.py"
ORACLE_SCRIPT = "/tests/oracle_pack_project.py"
N_TESTS = 50

def generate_random_dir(base_path, num_files, max_depth=4):
    for _ in range(num_files):
        depth = random.randint(0, max_depth)
        current_dir = base_path
        for _ in range(depth):
            dir_name = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 15)))
            current_dir = os.path.join(current_dir, dir_name)
        os.makedirs(current_dir, exist_ok=True)

        file_name = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 15)))
        file_path = os.path.join(current_dir, file_name)

        # 0 to 256 KB
        size = random.randint(0, 256 * 1024)
        with open(file_path, "wb") as f:
            f.write(os.urandom(size))

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    random.seed(42)

    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    with tempfile.TemporaryDirectory() as temp_dir:
        for i in range(N_TESTS):
            test_dir = os.path.join(temp_dir, f"test_dir_{i}")
            os.makedirs(test_dir)

            num_files = random.randint(1, 30)
            generate_random_dir(test_dir, num_files, max_depth=4)

            agent_archive = os.path.join(temp_dir, f"agent_archive_{i}.pack")
            oracle_archive = os.path.join(temp_dir, f"oracle_archive_{i}.pack")

            # Run agent
            agent_cmd = ["python3", AGENT_SCRIPT, test_dir, agent_archive]
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert agent_proc.returncode == 0, f"Agent script failed on test {i}:\nSTDOUT: {agent_proc.stdout}\nSTDERR: {agent_proc.stderr}"
            assert os.path.isfile(agent_archive), f"Agent script did not create output archive {agent_archive}"

            # Run oracle
            oracle_cmd = ["python3", ORACLE_SCRIPT, test_dir, oracle_archive]
            oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_proc.returncode == 0, f"Oracle script failed on test {i}:\nSTDOUT: {oracle_proc.stdout}\nSTDERR: {oracle_proc.stderr}"
            assert os.path.isfile(oracle_archive), f"Oracle script did not create output archive {oracle_archive}"

            # Compare archives
            agent_size = os.path.getsize(agent_archive)
            oracle_size = os.path.getsize(oracle_archive)

            if agent_size != oracle_size:
                pytest.fail(f"Archive size mismatch on test {i}. Agent: {agent_size} bytes, Oracle: {oracle_size} bytes")

            match = filecmp.cmp(agent_archive, oracle_archive, shallow=False)
            if not match:
                # Provide a bit more context if possible
                with open(agent_archive, "rb") as f1, open(oracle_archive, "rb") as f2:
                    agent_bytes = f1.read()
                    oracle_bytes = f2.read()
                    for j in range(len(agent_bytes)):
                        if agent_bytes[j] != oracle_bytes[j]:
                            pytest.fail(f"Archive content mismatch on test {i} at byte offset {j}. Agent: {hex(agent_bytes[j])}, Oracle: {hex(oracle_bytes[j])}")
                pytest.fail(f"Archive content mismatch on test {i}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
