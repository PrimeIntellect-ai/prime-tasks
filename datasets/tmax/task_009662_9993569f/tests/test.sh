#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

import pytest

SOURCE = "/home/user/extract_features.cpp"
EXECUTABLE = "/tmp/extract_features_test"
FEATURES = "/home/user/features.csv"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."

    try:
        subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE, "-o", EXECUTABLE],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Failed to compile {SOURCE}: {exc}")

    if os.path.exists(FEATURES):
        os.remove(FEATURES)

    try:
        subprocess.run(
            [EXECUTABLE],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Compiled feature extractor failed to run: {exc}")


def test_features_csv_exists():
    assert os.path.isfile(FEATURES), "/home/user/features.csv does not exist."


def test_features_csv_content():
    data_file = "/home/user/data.txt"
    assert os.path.isfile(data_file), "Original data file /home/user/data.txt is missing."

    with open(data_file, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 2, "data.txt must have exactly 2 lines."

    sequence = lines[0]
    signals = [float(x) for x in lines[1].split(",")]

    primer = "ATGCGAT"
    idx = sequence.find(primer)
    assert idx != -1, f"Primer {primer} not found in sequence."

    payload_start = idx + len(primer)
    signal_start = payload_start * 10

    assert len(signals) >= signal_start + 50, "Not enough signal samples for the payload."
    extracted_signal = signals[signal_start:signal_start + 50]

    N = 50
    expected_rows = ["Bin,Magnitude"]
    for k in range(N):
        re = 0.0
        im = 0.0
        for n in range(N):
            angle = 2.0 * math.pi * k * n / N
            re += extracted_signal[n] * math.cos(angle)
            im -= extracted_signal[n] * math.sin(angle)
        mag = math.sqrt(re * re + im * im)
        expected_rows.append(f"{k},{mag:.4f}")

    expected_csv = "\n".join(expected_rows) + "\n"

    with open(FEATURES, "r") as f:
        actual_csv = f.read()

    actual_csv_lines = [line.strip() for line in actual_csv.strip().split("\n")]
    expected_csv_lines = [line.strip() for line in expected_csv.strip().split("\n")]

    assert actual_csv_lines == expected_csv_lines, "The contents of features.csv do not match the expected DFT magnitudes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
