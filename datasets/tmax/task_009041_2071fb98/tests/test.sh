#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import random
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/forensics/log_analyzer.py"
REPORT_PATH = "/home/user/diagnostics_report.txt"


def generate_data(seed):
    random.seed(seed)
    num_points = random.randint(95, 105)
    return [random.gauss(40, 10) if random.random() < 0.5 else random.gauss(80, 10) for _ in range(num_points)]


def find_threshold(data):
    threshold = sum(data) / len(data)
    for _ in range(100):
        low = [x for x in data if x <= threshold]
        high = [x for x in data if x > threshold]

        if not low or not high:
            break

        new_threshold = (sum(low) / len(low) + sum(high) / len(high)) / 2.0

        if abs(new_threshold - threshold) < 0.001:
            break

        threshold = new_threshold
    else:
        raise ValueError("Convergence failed")

    return threshold


@pytest.fixture(scope="module")
def analyzer():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_log_analyzer", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_diagnostics_report():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]

    assert len(lines) == 50, f"Expected 50 lines in the report, but found {len(lines)}."
    assert len(raw_lines) == 50, "The report must contain exactly 50 physical lines with no blank lines."
    assert all(line == line.strip() and line for line in raw_lines), "Report lines must be nonblank and have no surrounding whitespace."

    expected_lines = []
    for seed in range(1, 51):
        data = generate_data(seed)
        thresh = find_threshold(data)
        expected_lines.append(f"Seed {seed}: {thresh:.2f}")

    for i, (actual, expected) in enumerate(zip(lines, expected_lines), 1):
        assert actual == expected, f"Mismatch at line {i}. Expected: '{expected}', Actual: '{actual}'"


def test_script_is_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Retain the original source-level assertions in addition to behavioral tests.
    assert "chunk = [data[i+j] for j in range(chunk_size)]" not in content, "The chunking IndexError bug is still present."
    assert "abs(" in content or "abs (" in content, "The convergence bug (missing abs() in threshold check) does not appear to be fixed."


def test_chunking_boundaries_and_data_preservation(analyzer):
    for chunk_size in (1, 2, 7, 10, 16):
        for length in (0, 1, chunk_size - 1, chunk_size, chunk_size + 1, 2 * chunk_size - 1, 2 * chunk_size, 2 * chunk_size + 3):
            if length < 0:
                continue
            data = list(range(length))
            chunks = analyzer.process_chunks(data, chunk_size=chunk_size)
            assert isinstance(chunks, list)
            assert all(isinstance(chunk, list) for chunk in chunks)
            assert all(0 < len(chunk) <= chunk_size for chunk in chunks)
            assert all(len(chunk) == chunk_size for chunk in chunks[:-1])
            flattened = [item for chunk in chunks for item in chunk]
            assert flattened == data, f"Chunking lost, duplicated, or reordered data for length={length}, chunk_size={chunk_size}"


def test_find_threshold_behavior(analyzer):
    datasets = [
        [1.0, 2.0, 3.0, 50.0, 51.0, 52.0],
        [-20.0, -19.0, -18.0, 3.0, 4.0, 100.0],
        [0.0, 0.1, 0.2, 9.0, 9.1, 30.0, 30.1],
        [5.0] * 8 + [25.0] * 7,
    ]
    private_rng = random.Random(secrets.randbits(128))
    for _ in range(20):
        left_center = private_rng.uniform(-100, 20)
        right_center = left_center + private_rng.uniform(15, 150)
        data = [private_rng.gauss(left_center, private_rng.uniform(0.2, 8.0)) for _ in range(private_rng.randint(20, 60))]
        data += [private_rng.gauss(right_center, private_rng.uniform(0.2, 8.0)) for _ in range(private_rng.randint(20, 60))]
        private_rng.shuffle(data)
        datasets.append(data)

    for data in datasets:
        expected = find_threshold(data)
        actual = analyzer.find_threshold(list(data))
        assert math.isfinite(actual)
        assert abs(actual - expected) <= 0.001, f"Incorrect threshold: expected {expected}, got {actual}"


def test_analyzer_cli_on_unannounced_seeds():
    # These cases are selected only after the agent has finished, so a fixed table
    # for the 50 report seeds cannot substitute for a working analyzer.
    dynamic_seeds = []
    while len(dynamic_seeds) < 12:
        seed = secrets.randbelow(2_000_000_000) + 1000
        if seed not in dynamic_seeds:
            dynamic_seeds.append(seed)

    for seed in dynamic_seeds:
        expected = f"Seed {seed}: {find_threshold(generate_data(seed)):.2f}"
        result = subprocess.run(
            ["python3", SCRIPT_PATH, "--seed", str(seed)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, f"Analyzer failed for seed {seed}: {result.stderr}"
        assert result.stderr == "", f"Analyzer wrote unexpected stderr for seed {seed}: {result.stderr}"
        assert result.stdout.splitlines() == [expected], f"Incorrect analyzer output for seed {seed}: {result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
