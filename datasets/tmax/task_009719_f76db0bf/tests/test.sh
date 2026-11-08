#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import stat
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "optimizer.rs")
RESULT = os.path.join(HOME, "result.txt")
TARGET = os.path.join(HOME, "target.txt")
PRIMER = os.path.join(HOME, "primer.txt")
MATRIX = os.path.join(HOME, "matrix.txt")
BINARY = "/tmp/optimizer_verified"


def expected_score(target, primer, matrix):
    order = "ACGT"
    index = {base: i for i, base in enumerate(order)}
    return max(
        sum(matrix[index[target[start + i]]][index[base]] for i, base in enumerate(primer))
        for start in range(len(target) - len(primer) + 1)
    )


def expected_root(score):
    low, high = 0.0, 10.0
    while math.exp(high) + score * high - 200.0 <= 0.0:
        high *= 2.0
    for _ in range(120):
        mid = (low + high) / 2.0
        if math.exp(mid) + score * mid - 200.0 < 0.0:
            low = mid
        else:
            high = mid
    return (low + high) / 2.0


def write_inputs(target, primer, matrix):
    with open(TARGET, "w") as f:
        f.write(target + "\n")
    with open(PRIMER, "w") as f:
        f.write(primer + "\n")
    with open(MATRIX, "w") as f:
        f.write("  A  C  G  T\n")
        for base, row in zip("ACGT", matrix):
            f.write(base + " " + " ".join(str(value) for value in row) + "\n")


def run_submission():
    if os.path.lexists(RESULT):
        os.unlink(RESULT)
    subprocess.run([BINARY], cwd=HOME, check=True, timeout=10)
    assert os.path.isfile(RESULT), "The compiled Rust program did not create /home/user/result.txt."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 result lines, got {len(lines)}."
    score_match = re.fullmatch(r"Max Score:\s*(-?\d+)", lines[0])
    root_match = re.fullmatch(r"Root:\s*([0-9]+\.[0-9]{4})", lines[1])
    assert score_match is not None, f"Invalid score output: {lines[0]!r}"
    assert root_match is not None, f"Invalid root output: {lines[1]!r}"
    return int(score_match.group(1)), float(root_match.group(1))


def test_00_optimizer_is_rust_and_processes_input_files():
    assert os.path.lexists(SOURCE), "Expected /home/user/optimizer.rs to exist."
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), "/home/user/optimizer.rs must be a regular file."
    assert source_stat.st_size > 0, "/home/user/optimizer.rs is empty."

    subprocess.run(
        ["rustc", SOURCE, "-O", "-o", BINARY],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    originals = {}
    for path in (TARGET, PRIMER, MATRIX):
        with open(path, "r") as f:
            originals[path] = f.read()

    try:
        alphabet = "ACGT"
        for _ in range(5):
            target_len = 18 + secrets.randbelow(13)
            primer_len = 4 + secrets.randbelow(min(7, target_len - 3))
            target = "".join(secrets.choice(alphabet) for _ in range(target_len))
            primer = "".join(secrets.choice(alphabet) for _ in range(primer_len))
            matrix = [[1 + secrets.randbelow(9) for _ in range(4)] for _ in range(4)]
            write_inputs(target, primer, matrix)

            wanted_score = expected_score(target, primer, matrix)
            wanted_root = expected_root(wanted_score)
            actual_score, actual_root = run_submission()
            assert actual_score == wanted_score, (
                f"Program returned score {actual_score}, expected {wanted_score} for generated inputs."
            )
            assert abs(actual_root - wanted_root) < 1e-4, (
                f"Program returned root {actual_root}, expected approximately {wanted_root:.4f}."
            )
    finally:
        for path, content in originals.items():
            with open(path, "w") as f:
                f.write(content)

    # Re-run on the provided inputs so the final result is produced by the artifact.
    run_submission()


def test_result_file_exists():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"Expected result file {result_path} does not exist."


def test_result_file_content():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"Expected result file {result_path} does not exist."

    with open(result_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {result_path}, got {len(lines)}."

    # Check max score
    assert "Max Score: 35" in lines[0], f"Expected first line to contain 'Max Score: 35', got '{lines[0]}'."

    # Check root
    # Allow slight variations like '4.0592'
    root_match = re.search(r"Root:\s*([0-9.]+)", lines[1])
    assert root_match is not None, f"Could not parse Root value from second line: '{lines[1]}'."

    root_val = float(root_match.group(1))
    assert abs(root_val - 4.0592) < 1e-4, f"Expected Root to be approximately 4.0592, got {root_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
