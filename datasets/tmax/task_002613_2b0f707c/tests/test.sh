#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random

def test_executable_exists():
    agent_path = '/home/user/project/bin/encoder_cli'
    assert os.path.isfile(agent_path), f"Executable {agent_path} is missing"
    assert os.access(agent_path, os.X_OK), f"Executable {agent_path} is not executable"

def test_fuzz_equivalence():
    oracle_path = '/tests/oracle_encoder_cli'
    agent_path = '/home/user/project/bin/encoder_cli'

    assert os.path.isfile(oracle_path), f"Oracle {oracle_path} missing"
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} missing"

    # Generate fuzz inputs
    random.seed(42)
    charset = [chr(i) for i in range(32, 127)]

    inputs = []
    for _ in range(1000):
        length = random.randint(5, 100)
        line = "".join(random.choices(charset, k=length))
        inputs.append(line)

    input_text = "\n".join(inputs) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_text,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_out = oracle_proc.stdout.splitlines()

    # Run agent
    env = os.environ.copy()
    # Add potential shared library paths to LD_LIBRARY_PATH in case the agent didn't set rpath
    project_dirs = [
        "/home/user/project",
        "/home/user/project/lib",
        "/home/user/project/bin",
        "/home/user/project/src"
    ]
    env["LD_LIBRARY_PATH"] = ":".join(project_dirs) + ":" + env.get("LD_LIBRARY_PATH", "")

    agent_proc = subprocess.run(
        [agent_path],
        input=input_text,
        text=True,
        capture_output=True,
        env=env
    )

    assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}\nstderr: {agent_proc.stderr}"

    agent_out = agent_proc.stdout.splitlines()

    assert len(oracle_out) == len(inputs), f"Oracle output length mismatch: expected {len(inputs)}, got {len(oracle_out)}"
    assert len(agent_out) == len(inputs), f"Agent output length mismatch: expected {len(inputs)}, got {len(agent_out)}"

    for i, (inp, o_out, a_out) in enumerate(zip(inputs, oracle_out, agent_out)):
        assert o_out == a_out, (
            f"Output mismatch on input {i}:\n"
            f"Input:  {repr(inp)}\n"
            f"Oracle: {repr(o_out)}\n"
            f"Agent:  {repr(a_out)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
