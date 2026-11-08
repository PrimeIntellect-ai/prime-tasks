#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import pytest


def video_parameters():
    proc = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-count_frames", "-show_entries", "stream=width,nb_read_frames",
            "-of", "json", "/app/cell_video.mp4"
        ],
        text=True,
        capture_output=True,
        timeout=10,
        check=True,
    )
    stream = json.loads(proc.stdout)["streams"][0]
    return int(stream["width"]), int(stream["nb_read_frames"])


def generate_input(seed):
    random.seed(seed)
    length = random.randint(10, 1000)
    seq = ''.join(random.choices("ACGT", k=length))
    seq_lines = '\n'.join(seq[i:i+80] for i in range(0, len(seq), 80))
    return f">fuzz_seq_{length}\n{seq_lines}\n"


def expected_output(fasta_input, width, frames):
    sequence = ''.join(
        line.strip()
        for line in fasta_input.splitlines()
        if not line.startswith(">")
    )

    mesh = [0.0] * width
    mesh[width // 2] = float(len(sequence))
    new_mesh = [0.0] * width

    for _ in range(frames):
        for i in range(1, width - 1):
            new_mesh[i] = mesh[i] + 0.25 * (
                mesh[i - 1] - 2.0 * mesh[i] + mesh[i + 1]
            )
        mesh, new_mesh = new_mesh, mesh

    return f"{mesh[width // 2]:.6f}"


def test_fuzz_equivalence():
    agent_solver = "/home/user/solver"

    assert os.path.isfile(agent_solver), f"Agent solver executable {agent_solver} is missing."
    assert os.access(agent_solver, os.X_OK), f"Agent solver {agent_solver} is not executable."

    width, frames = video_parameters()
    num_inputs = 50
    for i in range(num_inputs):
        fuzz_input = generate_input(i)
        expected = expected_output(fuzz_input, width, frames)

        try:
            agent_proc = subprocess.run(
                [agent_solver],
                input=fuzz_input,
                text=True,
                capture_output=True,
                timeout=5,
                check=True,
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on input {i}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input {i}")

        assert expected == agent_out, (
            f"Mismatch on input {i}:\n"
            f"Input:\n{fuzz_input}\n"
            f"Expected: {expected}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
