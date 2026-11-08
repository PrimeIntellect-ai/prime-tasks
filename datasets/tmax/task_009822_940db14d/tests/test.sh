#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import subprocess
import uuid

import pytest

PROJECT_DIR = "/home/user/data_prep"
INPUT_FILE = "/home/user/raw_sensors.csv"
OUTPUT_FILE = "/home/user/clean_norms.csv"
CARGO = "/opt/cargo/bin/cargo"

ORIGINAL_INPUT = """timestamp,x,y,z
2023-10-01T10:00:00Z,1.0,2.0,2.0
2023-10-01T10:01:00Z,0.0,0.0,0.0
2023-10-01T10:02:00Z,3.0,4.0,12.0
2023-10-01T10:03:00Z,invalid,1.0,1.0
2023-10-01T10:04:00Z,0.5,0.5,0.7071067811865476
2023-10-01T10:05:00Z,-6.0,8.0,0.0
"""


def run_project():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    env = os.environ.copy()
    env["RUSTUP_HOME"] = "/opt/rust"
    env["CARGO_HOME"] = "/opt/cargo"
    env["PATH"] = "/opt/cargo/bin:" + env.get("PATH", "")

    result = subprocess.run(
        [CARGO, "run", "--quiet", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml")],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"The Rust project failed to compile or run:\n{result.stdout}"
    assert os.path.isfile(OUTPUT_FILE), "Running the Rust program did not create clean_norms.csv."


@pytest.fixture(scope="session")
def run_original():
    with open(INPUT_FILE, "w", newline="") as f:
        f.write(ORIGINAL_INPUT)
    run_project()


def test_rust_project_exists():
    """Verify that the Rust project directory exists."""
    project_dir = "/home/user/data_prep"
    assert os.path.exists(project_dir), f"The project directory {project_dir} does not exist."
    assert os.path.isdir(project_dir), f"The path {project_dir} is not a directory."

    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    assert os.path.exists(cargo_toml), f"Cargo.toml not found in {project_dir}."


def test_clean_norms_csv_exists(run_original):
    """Verify that the output CSV file exists."""
    file_path = "/home/user/clean_norms.csv"
    assert os.path.exists(file_path), f"The output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_clean_norms_csv_content(run_original):
    """Verify that the output CSV file contains the correct processed data."""
    file_path = "/home/user/clean_norms.csv"

    expected_lines = [
        "timestamp,norm",
        "2023-10-01T10:00:00Z,3.0000",
        "2023-10-01T10:02:00Z,13.0000",
        "2023-10-01T10:04:00Z,1.0000",
        "2023-10-01T10:05:00Z,10.0000"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().split("\n")

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual.strip()}'."


def test_program_handles_changed_input(run_original):
    """Run the compiled project on unpredictable data and verify filtering and norms."""
    valid = []
    for _ in range(4):
        timestamp = f"dynamic-{uuid.uuid4().hex}"
        x = secrets.randbelow(39) - 19
        y = secrets.randbelow(39) - 19
        z = secrets.randbelow(39) - 19
        if x == 0 and y == 0 and z == 0:
            z = 1
        valid.append((timestamp, x, y, z))

    rows = [
        [valid[0][0], str(valid[0][1]), str(valid[0][2]), str(valid[0][3])],
        [f"bad-x-{uuid.uuid4().hex}", "not-a-float", "1", "2"],
        [f"zero-{uuid.uuid4().hex}", "0.0", "-0.0", "0"],
        [valid[1][0], str(valid[1][1]), str(valid[1][2]), str(valid[1][3])],
        [f"bad-y-{uuid.uuid4().hex}", "1", "corrupt", "2"],
        [valid[2][0], str(valid[2][1]), str(valid[2][2]), str(valid[2][3])],
        [f"bad-z-{uuid.uuid4().hex}", "1", "2", "invalid"],
        [valid[3][0], str(valid[3][1]), str(valid[3][2]), str(valid[3][3])],
    ]

    with open(INPUT_FILE, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "x", "y", "z"])
        writer.writerows(rows)

    run_project()

    with open(OUTPUT_FILE, "r", newline="") as f:
        actual = list(csv.reader(f))

    expected = [["timestamp", "norm"]]
    for timestamp, x, y, z in valid:
        norm = math.sqrt(float(x) ** 2 + float(y) ** 2 + float(z) ** 2)
        expected.append([timestamp, f"{norm:.4f}"])

    assert actual == expected, f"Changed-input output mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
