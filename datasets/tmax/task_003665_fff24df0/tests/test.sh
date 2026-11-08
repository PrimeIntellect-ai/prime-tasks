#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import string
import tempfile
import subprocess
import gzip

NUM_TESTS = 50

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits + " \n\t.,?!", k=length))

def create_fuzz_directory(base_dir):
    depth = random.randint(1, 5)

    dirs = [base_dir]
    current = base_dir
    for i in range(depth):
        d = os.path.join(current, f"dir_{i}")
        os.makedirs(d)
        dirs.append(d)
        current = d

    num_files = random.randint(2, 10)
    for i in range(num_files):
        d = random.choice(dirs)
        f_path = os.path.join(d, f"file_{i}.md")
        with open(f_path, 'w') as f:
            f.write(generate_random_string(random.randint(0, 5000)))

    num_symlinks = random.randint(2, 5)
    for i in range(num_symlinks):
        src_dir = random.choice(dirs)
        target_dir = random.choice(dirs)
        link_path = os.path.join(src_dir, f"link_{i}")
        if not os.path.exists(link_path):
            os.symlink(target_dir, link_path)

def test_fuzz_equivalence():
    agent_script = "/home/user/doc_builder.py"
    oracle_script = "/tests/oracle_doc_builder.py"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    for i in range(NUM_TESTS):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = os.path.join(temp_dir, "input")
            os.makedirs(input_dir)
            create_fuzz_directory(input_dir)

            oracle_out = os.path.join(temp_dir, "oracle.gz")
            agent_out = os.path.join(temp_dir, "agent.gz")

            subprocess.run([sys.executable, oracle_script, input_dir, oracle_out], check=True)

            res = subprocess.run([sys.executable, agent_script, input_dir, agent_out], capture_output=True, text=True)
            assert res.returncode == 0, f"Agent script failed on fuzz test {i}. Stderr: {res.stderr}"

            assert os.path.exists(agent_out), f"Agent script did not produce output file {agent_out}"

            try:
                with gzip.open(oracle_out, 'rb') as f:
                    oracle_data = f.read()
            except Exception as e:
                raise AssertionError(f"Failed to read oracle output: {e}")

            try:
                with gzip.open(agent_out, 'rb') as f:
                    agent_data = f.read()
            except Exception as e:
                raise AssertionError(f"Failed to read agent output as gzip: {e}")

            assert oracle_data == agent_data, f"Output mismatch on fuzz test {i}. Agent output does not match oracle."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
