#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/cleaner")
CSV_PATH = Path("/home/user/transactions.csv")
SUM_PATH = Path("/home/user/sum.txt")


def test_rust_project_exists():
    project_dir = "/home/user/cleaner"
    assert os.path.isdir(project_dir), f"The Rust project directory {project_dir} does not exist."

    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    src_dir = os.path.join(project_dir, "src")
    main_rs = os.path.join(src_dir, "main.rs")

    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {project_dir}. Did you initialize the Rust project correctly?"
    assert os.path.isdir(src_dir), f"src directory not found in {project_dir}."
    assert os.path.isfile(main_rs), f"main.rs not found in {src_dir}."


def run_program_and_check(rows, expected):
    lines = ["user_id,transaction_id,amount"]
    for index, value in enumerate(rows):
        field = "" if value is None else str(value)
        lines.append(f"U{index},{field},{index}.0")
    CSV_PATH.write_text("\n".join(lines) + "\n")

    if SUM_PATH.exists():
        SUM_PATH.unlink()

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust project did not compile and run successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert SUM_PATH.is_file(), "Running the Rust program did not create /home/user/sum.txt."
    actual = SUM_PATH.read_text().strip()
    assert actual == str(expected), (
        f"Program produced {actual!r}, but the exact u64 sum is {expected!r}."
    )


def test_rust_program_executes_and_aggregates_exact_u64_values():
    original_csv = CSV_PATH.read_bytes()
    try:
        # An unpredictable odd integer above 2^53 detects float parsing and
        # prevents a fixed, precomputed answer from satisfying the verifier.
        large_odd = (1 << 53) + 1 + 2 * secrets.randbelow(1_000_000_000)
        run_program_and_check([None, large_odd, None], large_odd)

        values = [
            (1 << 53) + 3 + 2 * secrets.randbelow(100_000),
            17 + secrets.randbelow(100_000),
            None,
            4_000_000_000 + secrets.randbelow(100_000),
        ]
        run_program_and_check(values, sum(value or 0 for value in values))

        # Ensure the parser accepts the full unsigned 64-bit range.
        run_program_and_check([None, (1 << 64) - 1], (1 << 64) - 1)
    finally:
        CSV_PATH.write_bytes(original_csv)

    # Run once more against the task's original dataset so the required final
    # artifact reflects that dataset.
    if SUM_PATH.exists():
        SUM_PATH.unlink()
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust project failed when run against the original dataset.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_sum_txt_exists_and_correct():
    sum_file_path = "/home/user/sum.txt"
    assert os.path.isfile(sum_file_path), f"The file {sum_file_path} does not exist. Did you run your Rust program?"

    with open(sum_file_path, "r") as f:
        content = f.read().strip()

    expected_sum = "27021597764222989"
    assert content == expected_sum, f"The sum in {sum_file_path} is incorrect. Expected '{expected_sum}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
