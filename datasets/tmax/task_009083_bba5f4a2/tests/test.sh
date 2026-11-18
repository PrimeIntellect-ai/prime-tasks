#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

FEATURES = Path("/home/user/data/features.csv")
EXPERIMENTS = Path("/home/user/experiments.txt")
RAW = Path("/home/user/data/raw_sensors.csv")
PROJECT = Path("/home/user/sensor_pipeline")


def test_features_csv():
    assert FEATURES.is_file(), f"Output file {FEATURES} does not exist."

    with FEATURES.open("r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 6, f"Expected 6 lines in {FEATURES} (header + 5 rows), found {len(lines)}."

    expected_header = "timestamp,sensor_A,sensor_B,diff,magnitude"
    assert lines[0] == expected_header, f"Header mismatch. Expected '{expected_header}', got '{lines[0]}'."

    expected_rows = [
        "1600000000,10.0,5.0,5.0,11.1803",
        "1600000060,12.0,9.0,3.0,15.0000",
        "1600000120,8.0,15.0,-7.0,17.0000",
        "1600000180,-3.0,4.0,-7.0,5.0000",
        "1600000240,0.0,0.0,0.0,0.0000"
    ]

    for i, expected_row in enumerate(expected_rows):
        assert lines[i + 1] == expected_row, f"Row {i+1} mismatch. Expected '{expected_row}', got '{lines[i+1]}'."


def test_experiments_txt():
    assert EXPERIMENTS.is_file(), f"Log file {EXPERIMENTS} does not exist."

    with EXPERIMENTS.open("r") as f:
        content = f.read().strip()

    expected_log = "SUCCESS: Processed 5 rows."
    assert expected_log in content, f"Expected log '{expected_log}' not found in {EXPERIMENTS}."


def test_rust_project_files():
    cargo_toml = PROJECT / "Cargo.toml"
    main_rs = PROJECT / "src/main.rs"

    assert cargo_toml.is_file(), f"Rust project file {cargo_toml} does not exist."
    assert main_rs.is_file(), f"Rust source file {main_rs} does not exist."


def test_rust_pipeline_on_unseen_input():
    assert (PROJECT / "Cargo.toml").is_file()
    assert (PROJECT / "src/main.rs").is_file()

    original_raw = RAW.read_bytes()
    original_features = FEATURES.read_bytes() if FEATURES.exists() else None
    original_experiments = EXPERIMENTS.read_bytes() if EXPERIMENTS.exists() else None

    count = 3 + secrets.randbelow(5)
    base_timestamp = 1700000000 + secrets.randbelow(10000000)
    rows = []
    for i in range(count):
        a_int = secrets.randbelow(40001) - 20000
        b_int = secrets.randbelow(40001) - 20000
        # Distinct denominators and six-decimal input make fixed-output solutions
        # ineffective while keeping expected numeric results deterministic.
        a_text = f"{a_int / 37.0:.6f}"
        b_text = f"{b_int / 53.0:.6f}"
        rows.append((str(base_timestamp + i * 61), a_text, b_text))

    try:
        with RAW.open("w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "sensor_A", "sensor_B"])
            writer.writerows(rows)

        FEATURES.unlink(missing_ok=True)
        EXPERIMENTS.unlink(missing_ok=True)

        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            "The Rust project did not build and run successfully.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert FEATURES.is_file(), "Running the Rust program did not create features.csv."
        assert EXPERIMENTS.is_file(), "Running the Rust program did not create experiments.txt."

        with FEATURES.open(newline="") as f:
            output = list(csv.reader(f))

        expected_header = ["timestamp", "sensor_A", "sensor_B", "diff", "magnitude"]
        assert output, "features.csv is empty."
        assert output[0] == expected_header, f"Header mismatch after execution: {output[0]}"
        assert len(output) == count + 1, f"Expected {count} output rows, got {len(output) - 1}."

        for index, (actual, source) in enumerate(zip(output[1:], rows), start=1):
            assert len(actual) == 5, f"Output row {index} has {len(actual)} columns instead of 5."
            timestamp, a_text, b_text = source
            a = float(a_text)
            b = float(b_text)
            assert actual[0] == timestamp, f"Timestamp mismatch in dynamic row {index}."
            assert math.isclose(float(actual[1]), a, rel_tol=0, abs_tol=1e-9)
            assert math.isclose(float(actual[2]), b, rel_tol=0, abs_tol=1e-9)
            assert math.isclose(float(actual[3]), a - b, rel_tol=0, abs_tol=1e-9), f"Incorrect diff in row {index}."
            assert re.fullmatch(r"-?\d+\.\d{4}", actual[4]), f"Magnitude in row {index} is not formatted to exactly 4 decimal places."
            expected_magnitude = math.sqrt(a * a + b * b)
            assert math.isclose(float(actual[4]), expected_magnitude, rel_tol=0, abs_tol=0.000051), f"Incorrect magnitude in row {index}."

        log_content = EXPERIMENTS.read_text().strip()
        assert log_content == f"SUCCESS: Processed {count} rows.", f"Unexpected execution log: {log_content!r}"
    finally:
        RAW.write_bytes(original_raw)
        if original_features is None:
            FEATURES.unlink(missing_ok=True)
        else:
            FEATURES.write_bytes(original_features)
        if original_experiments is None:
            EXPERIMENTS.unlink(missing_ok=True)
        else:
            EXPERIMENTS.write_bytes(original_experiments)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
