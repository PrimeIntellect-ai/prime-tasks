#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path("/home/user/etl_pipeline")
SOURCE = PROJECT / "src/main.rs"
DATASET = Path("/home/user/data/dataset.csv")
OUTPUT = Path("/home/user/nearest_neighbor.txt")


def expected_from_text(text):
    data = []
    for line in text.strip().splitlines():
        if line:
            parts = line.split(',')
            data.append((float(parts[0]), float(parts[1])))

    assert len(data) == 10, "Dataset must contain exactly 10 rows"
    train_data = data[:8]
    test_data = data[8:]

    min_f1 = min(row[0] for row in train_data)
    max_f1 = max(row[0] for row in train_data)
    min_f2 = min(row[1] for row in train_data)
    max_f2 = max(row[1] for row in train_data)

    assert max_f1 != min_f1 and max_f2 != min_f2

    def scale(row):
        return (
            (row[0] - min_f1) / (max_f1 - min_f1),
            (row[1] - min_f2) / (max_f2 - min_f2),
        )

    scaled_train = [scale(row) for row in train_data]
    target = scale(test_data[0])
    distances = [
        math.sqrt((target[0] - row[0]) ** 2 + (target[1] - row[1]) ** 2)
        for row in scaled_train
    ]
    best_idx = min(range(len(distances)), key=distances.__getitem__)
    return f"{best_idx},{distances[best_idx]:.4f}", sorted(distances)


def get_expected_result():
    if not DATASET.exists():
        pytest.fail(f"Dataset missing at {DATASET}")
    return expected_from_text(DATASET.read_text())[0]


def make_random_dataset():
    while True:
        rows = [
            (secrets.randbelow(301) - 150, secrets.randbelow(301) - 150)
            for _ in range(10)
        ]
        text = "".join(f"{x},{y}\n" for x, y in rows)
        try:
            expected, distances = expected_from_text(text)
        except AssertionError:
            continue

        # Avoid ambiguous nearest neighbors and rounding-boundary edge cases.
        if distances[1] - distances[0] < 1e-7:
            continue
        distance = float(expected.split(',')[1])
        exact_distance = distances[0]
        scaled = exact_distance * 10000
        if abs((scaled - math.floor(scaled)) - 0.5) < 1e-6:
            continue
        return text, expected


def test_compiled_program_generates_results():
    assert SOURCE.exists(), f"Rust source is missing: {SOURCE}"
    assert stat.S_ISREG(SOURCE.stat().st_mode), f"Rust source is not a regular file: {SOURCE}"
    assert SOURCE.stat().st_size > 0, f"Rust source is empty: {SOURCE}"
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing"
    assert DATASET.is_file(), f"Dataset missing at {DATASET}"

    original_dataset = DATASET.read_bytes()
    target_dir = tempfile.mkdtemp(prefix="etl-verifier-target-")
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = target_dir

    def run_program(dataset_text, expected):
        DATASET.write_text(dataset_text)
        if OUTPUT.exists():
            OUTPUT.unlink()

        subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
            cwd=str(PROJECT),
            env=env,
            check=True,
            timeout=60,
        )

        assert DATASET.read_text() == dataset_text, "Program must not modify the input dataset"
        assert OUTPUT.is_file(), f"Output file is missing: {OUTPUT}"
        content = OUTPUT.read_text().strip()
        assert content == expected, f"Expected output '{expected}', but got '{content}'"

    try:
        # Exercise the compiled Rust artifact on verifier-generated inputs.
        for _ in range(3):
            dataset_text, expected = make_random_dataset()
            run_program(dataset_text, expected)

        # Restore the task dataset, run the program, and retain the original exact check.
        DATASET.write_bytes(original_dataset)
        expected_content = get_expected_result()
        run_program(original_dataset.decode(), expected_content)

        content = OUTPUT.read_text().strip()
        assert content == expected_content, f"Expected output '{expected_content}', but got '{content}'"
    finally:
        DATASET.write_bytes(original_dataset)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
