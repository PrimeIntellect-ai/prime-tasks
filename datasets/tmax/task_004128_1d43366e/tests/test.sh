#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import pytest


def test_fuzz_equivalence():
    agent_bin = "/home/user/dataset_tool"
    oracle_bin = "/tests/ref_tool"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"
    assert os.path.isfile(oracle_bin), f"Test oracle not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Test oracle at {oracle_bin} is not executable"

    with open(agent_bin, "rb") as f:
        agent_binary_data = f.read()
    with open(oracle_bin, "rb") as f:
        oracle_binary_data = f.read()
    assert agent_binary_data != oracle_binary_data, "Agent binary is byte-identical to the reference implementation"

    shutil.rmtree("/tmp/oracle_out", ignore_errors=True)
    shutil.rmtree("/tmp/agent_out", ignore_errors=True)
    os.makedirs("/tmp/agent_out")

    random.seed(42)
    oracle_cmds = []
    agent_cmds = []
    inputs = []

    for i in range(1000):
        offset = random.randrange(0, 10000000 + 1, 2)
        length = random.randrange(100, 500000 + 1, 2)
        scale = random.uniform(0.1, 10.0)
        inputs.append((offset, length, scale))
        oracle_cmds.append(f"extract {offset} {length} {scale:.6f} /tmp/oracle_out/{i}.raw\n")
        agent_cmds.append(f"extract {offset} {length} {scale:.6f} /tmp/agent_out/{i}.raw\n")

    # Run the submitted program before creating any ground-truth output files.
    agent_proc = subprocess.run(
        [agent_bin], input="".join(agent_cmds), text=True, capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent program crashed or failed: {agent_proc.stderr}"

    os.makedirs("/tmp/oracle_out")
    oracle_proc = subprocess.run(
        [oracle_bin], input="".join(oracle_cmds), text=True, capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"

    for i in range(1000):
        offset, length, scale = inputs[i]
        oracle_file = f"/tmp/oracle_out/{i}.raw"
        agent_file = f"/tmp/agent_out/{i}.raw"

        assert os.path.exists(oracle_file), f"Oracle failed to produce {oracle_file}"
        assert os.path.exists(agent_file), (
            f"Agent failed to produce output file for instruction: "
            f"extract {offset} {length} {scale:.6f} {agent_file}\n"
            f"Agent stderr: {agent_proc.stderr}"
        )

        with open(oracle_file, "rb") as f:
            oracle_data = f.read()
        with open(agent_file, "rb") as f:
            agent_data = f.read()

        if oracle_data != agent_data:
            pytest.fail(
                f"Output mismatch on instruction {i}:\n"
                f"Command: extract {offset} {length} {scale:.6f} <output_path>\n"
                f"Oracle output size: {len(oracle_data)} bytes\n"
                f"Agent output size: {len(agent_data)} bytes\n"
                f"Data differs!"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
