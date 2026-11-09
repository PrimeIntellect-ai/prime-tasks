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
import gzip
import pytest

ORACLE_PATH = "/tests/oracle_archive_scanner"
AGENT_PATH = "/home/user/archive_scanner"
NUM_TESTS = 20

def generate_random_string(length=20):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def create_random_tree(base_dir, max_depth=4):
    dirs = [base_dir]
    for _ in range(random.randint(1, max_depth)):
        parent = random.choice(dirs)
        new_dir = os.path.join(parent, generate_random_string(8))
        os.makedirs(new_dir, exist_ok=True)
        dirs.append(new_dir)
    return dirs

def create_test_environment(base_dir):
    dirs = create_random_tree(base_dir)

    num_zz = random.randint(0, 15)
    num_other = random.randint(0, 15)

    for _ in range(num_zz):
        target_dir = random.choice(dirs)
        file_path = os.path.join(target_dir, generate_random_string(8) + ".zz")

        lines = []
        num_lines = random.randint(1, 100)
        num_errors = random.randint(0, min(5, num_lines))

        error_indices = set(random.sample(range(num_lines), num_errors))
        for i in range(num_lines):
            line = generate_random_string(50)
            if i in error_indices:
                # Insert ERROR somewhere
                insert_idx = random.randint(0, len(line))
                line = line[:insert_idx] + "ERROR" + line[insert_idx:]
            lines.append(line)

        content = "\n".join(lines) + "\n"
        with gzip.open(file_path, "wt") as f:
            f.write(content)

    for _ in range(num_other):
        target_dir = random.choice(dirs)
        ext = random.choice([".txt", ".tar.gz", ".log", ".bin", ""])
        file_path = os.path.join(target_dir, generate_random_string(8) + ext)
        with open(file_path, "w") as f:
            f.write(generate_random_string(100))

@pytest.mark.parametrize("seed", range(NUM_TESTS))
def test_fuzz_equivalence(seed):
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"
    assert os.path.isfile(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

    random.seed(seed)

    with tempfile.TemporaryDirectory() as temp_dir:
        create_test_environment(temp_dir)

        try:
            oracle_res = subprocess.run([ORACLE_PATH, temp_dir], capture_output=True, text=True, timeout=5)
            agent_res = subprocess.run([AGENT_PATH, temp_dir], capture_output=True, text=True, timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail("Execution timed out.")

        assert agent_res.returncode == oracle_res.returncode, f"Exit code mismatch. Oracle: {oracle_res.returncode}, Agent: {agent_res.returncode}. Agent stderr: {agent_res.stderr}"
        assert agent_res.stdout == oracle_res.stdout, f"Stdout mismatch. Oracle: {repr(oracle_res.stdout)}, Agent: {repr(agent_res.stdout)}. Agent stderr: {agent_res.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
