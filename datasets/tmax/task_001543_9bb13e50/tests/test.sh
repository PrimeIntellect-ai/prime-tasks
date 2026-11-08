#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random


def test_video_sum_correct():
    path = "/home/user/video_sum.txt"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "582390", f"Expected sum 582390, got {content}"


def test_frame_decoder_fuzz_equivalence():
    agent_bin = "/home/user/frame_decoder"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable"

    random.seed(42)
    n_iterations = 10000
    size = 4096
    magic = b'\xde\xad\xbe\xef'

    for i in range(n_iterations):
        if i % 10 == 0:
            data = bytearray(random.getrandbits(8) for _ in range(size))
            data[0:4] = magic
            input_data = bytes(data)
        else:
            input_data = bytes(random.getrandbits(8) for _ in range(size))

        if input_data[:4] == magic:
            expected_returncode = 0
            expected_stdout = f"{sum(input_data[4:])}\n".encode()
        else:
            expected_returncode = 1
            expected_stdout = b""

        proc_agent = subprocess.run(
            [agent_bin],
            input=input_data,
            capture_output=True
        )

        assert proc_agent.returncode == expected_returncode, (
            f"Return code mismatch on iteration {i}. Expected: "
            f"{expected_returncode}, Agent: {proc_agent.returncode}"
        )
        assert proc_agent.stdout == expected_stdout, (
            f"Stdout mismatch on iteration {i}. Expected: "
            f"{expected_stdout!r}, Agent: {proc_agent.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
