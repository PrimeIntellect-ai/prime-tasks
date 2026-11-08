#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

SOURCE_PATH = "/home/user/eval_primer.c"
AGENT_PATH = "/home/user/eval_primer"
VIDEO_PATH = "/app/matrix.mp4"


def extract_matrix():
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO_PATH,
         "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")

    frame_size = 100 * 100
    assert len(result.stdout) == 16 * frame_size, (
        f"Expected 16 100x100 frames, got {len(result.stdout)} raw bytes"
    )

    values = []
    for i in range(16):
        frame = result.stdout[i * frame_size:(i + 1) * frame_size]
        values.append(sum(frame) / (frame_size * 255.0))
    return [values[i * 4:(i + 1) * 4] for i in range(4)]


def expected_output(matrix, seq):
    bases = "ACGT"
    b = [float(seq.count(base)) for base in bases]

    a = [[0.0] * 5 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            a[i][j] = sum(matrix[k][i] * matrix[k][j] for k in range(4))
        a[i][i] += 0.05
        a[i][4] = sum(matrix[k][i] * b[k] for k in range(4))

    for i in range(4):
        pivot = max(range(i, 4), key=lambda row: abs(a[row][i]))
        a[i], a[pivot] = a[pivot], a[i]
        for row in range(i + 1, 4):
            factor = a[row][i] / a[i][i]
            for col in range(i, 5):
                a[row][col] -= a[i][col] * factor

    x = [0.0] * 4
    for i in range(3, -1, -1):
        x[i] = (a[i][4] - sum(a[i][j] * x[j] for j in range(i + 1, 4))) / a[i][i]

    return " ".join(f"{value:.6f}" for value in x)


def test_eval_primer_equivalence():
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} is missing."

    compile_result = subprocess.run(
        ["gcc", "-O2", "-o", AGENT_PATH, SOURCE_PATH, "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Source failed to compile:\n{compile_result.stderr}"
    )

    assert os.path.exists(AGENT_PATH), f"Agent executable {AGENT_PATH} is missing."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable."

    matrix = extract_matrix()
    rng = random.SystemRandom()
    chars = "ACGT"
    sequences = [
        "A" * 10,
        "C" * 10,
        "G" * 10,
        "T" * 10,
        "ACGT" * 10,
    ]
    for _ in range(95):
        length = rng.randint(10, 50)
        sequences.append("".join(rng.choice(chars) for _ in range(length)))

    output_pattern = re.compile(r"^-?\d+\.\d{6} -?\d+\.\d{6} -?\d+\.\d{6} -?\d+\.\d{6}\n?$")

    for seq in sequences:
        result = subprocess.run(
            [AGENT_PATH, seq], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, (
            f"Agent program failed on input {seq} with stderr: {result.stderr}"
        )
        assert result.stderr == "", f"Unexpected stderr on input {seq}: {result.stderr}"
        assert output_pattern.fullmatch(result.stdout), (
            f"Output has the wrong format on input {seq}: {result.stdout!r}"
        )

        actual = result.stdout.strip()
        expected = expected_output(matrix, seq)
        assert actual == expected, (
            f"Mismatch on input {seq}.\nExpected: {expected}\nGot: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
