#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string


def expected_embedding(line, data):
    if line == "":
        return "0,0,0,0"

    values = line.encode("ascii")
    length = len(values)
    emb = [0, 0, 0, 0]

    for i in range(4):
        for k in range(1024):
            byte_val = data[i * 1024 + k]
            char_val = values[k % length]
            emb[i] = (emb[i] + byte_val * (char_val + 1)) % 10007

    return ",".join(str(value) for value in emb)


def test_embedder_fuzz_equivalence():
    agent_exec = "/home/user/embedder"

    assert os.path.isfile(agent_exec), f"Agent executable not found at {agent_exec}"
    assert os.access(agent_exec, os.X_OK), f"Agent file at {agent_exec} is not executable"

    with open("/app/experiment_video.mp4", "rb") as video:
        data = video.read(4096)
    assert len(data) == 4096, "Reference artifact does not contain 4096 bytes"

    random.seed(42)
    charset = string.ascii_letters + string.digits
    inputs = [""]

    for _ in range(1000):
        length = random.randint(1, 200)
        inputs.append(''.join(random.choice(charset) for _ in range(length)))

    input_data = "\n".join(inputs) + "\n"
    expected_output = [expected_embedding(line, data) for line in inputs]

    agent_proc = subprocess.run(
        [agent_exec],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, (
        "Agent executable crashed or returned non-zero exit code. "
        f"Stderr: {agent_proc.stderr}"
    )

    agent_output = agent_proc.stdout.splitlines()

    assert len(agent_output) == len(expected_output), (
        f"Output line count mismatch. Expected {len(expected_output)} lines, "
        f"got {len(agent_output)} lines."
    )

    for i, (inp, expected_line, agent_line) in enumerate(
        zip(inputs, expected_output, agent_output)
    ):
        assert expected_line == agent_line, (
            f"Mismatch on line {i + 1}.\n"
            f"Input: {repr(inp)}\n"
            f"Expected output: {expected_line}\n"
            f"Agent output: {agent_line}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
