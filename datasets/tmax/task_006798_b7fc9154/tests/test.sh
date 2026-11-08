#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SOURCE = "/home/user/find_k.rs"
OUTPUT = "/home/user/optimal_k.txt"
TARGET = "/home/user/target.txt"
BINARY = "/tmp/find_k_verified"


def expected_k(target):
    best_index = None
    best_mse = None
    for index in range(101):
        k = index * 0.01
        y = 100.0
        generated = []
        for step in range(1, 101):
            y = y + (-k * y) * 0.1
            if step % 10 == 0:
                generated.append(y)
        mse = sum((a - b) ** 2 for a, b in zip(generated, target)) / 10.0
        if best_mse is None or mse < best_mse:
            best_mse = mse
            best_index = index
    return f"{best_index / 100.0:.2f}"


def run_program():
    result = subprocess.run(
        [BINARY], cwd="/home/user", text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}: {result.stderr}"
    )
    assert result.stderr == "", f"Program wrote unexpected stderr: {result.stderr!r}"
    assert re.fullmatch(r"(?:0\.\d{2}|1\.00)\n?", result.stdout), (
        f"Program output was not only one k value formatted to two decimals: {result.stdout!r}"
    )
    return result.stdout.strip()


def write_target(values):
    with open(TARGET, "w") as f:
        f.write("\n".join(format(value, ".17g") for value in values) + "\n")


def euler_target(k):
    y = 100.0
    values = []
    for step in range(1, 101):
        y = y + (-k * y) * 0.1
        if step % 10 == 0:
            values.append(y)
    return values


def test_complete_solution():
    # Preserve the original verifier's existence and exact-output assertions.
    assert os.path.isfile(SOURCE), f"The Rust source file {SOURCE} is missing."
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == "0.34", (
        f"Expected {OUTPUT} to contain exactly '0.34', but found '{content}'."
    )

    compilation = subprocess.run(
        ["rustc", SOURCE, "-o", BINARY],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert compilation.returncode == 0, f"Rust source failed to compile:\n{compilation.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    with open(TARGET, "rb") as f:
        original_target = f.read()

    try:
        original_values = [float(line) for line in original_target.splitlines()]
        assert len(original_values) == 10
        original_expected = expected_k(original_values)
        assert original_expected == "0.34"
        assert run_program() == original_expected

        # Exact Euler-generated data at a different grid point distinguishes the
        # required recurrence and grid search from a fabricated constant answer.
        generated_values = euler_target(0.67)
        write_target(generated_values)
        assert run_program() == expected_k(generated_values)

        # A non-model-shaped target exercises evaluation of the complete grid.
        irregular_values = [
            91.0, 72.5, 58.0, 44.0, 35.5,
            29.0, 20.0, 17.5, 11.0, 9.5,
        ]
        write_target(irregular_values)
        assert run_program() == expected_k(irregular_values)
    finally:
        with open(TARGET, "wb") as f:
            f.write(original_target)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
