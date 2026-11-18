#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import random
import tempfile
import pytest

def test_files_exist():
    """Verify that the required files exist."""
    assert os.path.exists("/home/user/job.proto"), "/home/user/job.proto is missing"
    assert os.path.exists("/home/user/emulator.py"), "/home/user/emulator.py is missing"
    assert os.path.exists("/tests/reference_oracle.py"), "/tests/reference_oracle.py is missing"

def test_fuzz_equivalence():
    """Fuzz test the student's emulator against the reference oracle."""
    sys.path.insert(0, "/home/user")
    try:
        import job_pb2
    except ImportError:
        pytest.fail("Failed to import job_pb2. Did you compile job.proto in /home/user?")

    random.seed(42)
    N = 50

    env = os.environ.copy()
    env["PYTHONPATH"] = "/home/user:" + env.get("PYTHONPATH", "")

    for i in range(N):
        prog = job_pb2.Program()
        num_instructions = random.randint(10, 500)
        for _ in range(num_instructions):
            inst = prog.instructions.add()
            inst.op = random.choice([0, 1, 2])
            if inst.op == 0:
                inst.u = random.randint(1, 50)
            elif inst.op == 1:
                inst.u = random.randint(1, 50)
                inst.v = random.randint(1, 50)

        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
            tmp.write(prog.SerializeToString())
            tmp_path = tmp.name

        try:
            oracle_cmd = ["python3", "/tests/reference_oracle.py", tmp_path]
            agent_cmd = ["python3", "/home/user/emulator.py", tmp_path]

            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, env=env)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, env=env)

            assert oracle_res.returncode == 0, f"Oracle failed on input {i}:\nStderr: {oracle_res.stderr}"
            assert agent_res.returncode == 0, f"Emulator failed on input {i}:\nStderr: {agent_res.stderr}"

            expected = oracle_res.stdout.strip()
            actual = agent_res.stdout.strip()

            assert actual == expected, (
                f"Mismatch on fuzz input {i}.\n"
                f"Number of instructions: {num_instructions}\n"
                f"Expected output: {expected}\n"
                f"Actual output: {actual}"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
