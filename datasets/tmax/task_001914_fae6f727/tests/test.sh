#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/bayes_prep")
MANIFEST = PROJECT / "Cargo.toml"
INPUT = Path("/home/user/sensor_data.csv")
CLEANED = Path("/home/user/cleaned_data.csv")
METRICS = Path("/home/user/metrics.txt")


def test_cleaned_data_csv():
    file_path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. Did the Rust program run and produce the output?"

    expected_lines = [
        "sensor_id,successes,trials",
        "1,10,20",
        "2,15,30",
        "3,12,25",
        "4,5,10",
        "5,19,40"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    # Normalize carriage returns if any
    content = [line.strip() for line in content if line.strip()]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} in {file_path} is incorrect. Expected '{expected}', got '{actual}'."


def test_metrics_txt():
    file_path = "/home/user/metrics.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. Did the Rust program generate the metrics log?"

    expected_lines = [
        "Posterior Alpha: 32.0000",
        "Posterior Beta: 35.0000",
        "Posterior Mean: 0.4776"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    content = [line.strip() for line in content if line.strip()]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} in {file_path} is incorrect. Expected '{expected}', got '{actual}'."


def rust_binary_name():
    assert PROJECT.is_dir(), "The required Rust project /home/user/bayes_prep is missing."
    assert MANIFEST.is_file(), "The Rust project is missing Cargo.toml."

    result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(MANIFEST)],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Cargo could not read the project:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    manifest_real = MANIFEST.resolve()
    packages = [p for p in metadata["packages"] if Path(p["manifest_path"]).resolve() == manifest_real]
    assert len(packages) == 1, "Could not identify the package defined by /home/user/bayes_prep/Cargo.toml."

    package = packages[0]
    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Cargo project does not define a Rust binary program."
    default_run = package.get("default_run")
    if default_run:
        bins = [t for t in bins if t["name"] == default_run]
        assert bins, "Cargo's default-run does not name a binary target."
    else:
        assert len(bins) == 1, "Multiple binaries are present but Cargo.toml has no default-run."

    source = Path(bins[0]["src_path"])
    assert source.is_file() and source.suffix == ".rs", "The binary target must have a Rust source file."
    try:
        source.resolve().relative_to(PROJECT.resolve())
    except ValueError:
        pytest.fail("The Rust binary source must be inside /home/user/bayes_prep.")
    return bins[0]["name"]


def test_rust_project_compiles():
    binary = rust_binary_name()
    result = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", str(MANIFEST), "--bin", binary],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert result.returncode == 0, f"The Rust project does not compile:\n{result.stdout}\n{result.stderr}"


def make_case(row_count):
    rng = secrets.SystemRandom()
    rows = []
    missing_positions = {1, row_count // 2, row_count - 1}
    for i in range(row_count):
        trials = rng.randint(8, 90)
        successes = None if i in missing_positions else rng.randint(0, trials)
        sensor_id = str(rng.randrange(100000, 999999))
        rows.append((sensor_id, successes, trials))
    return rows


def expected_for(rows):
    known = [(successes, trials) for _, successes, trials in rows if successes is not None]
    alpha = 2.0 + sum(successes for successes, _ in known)
    beta = 5.0 + sum(trials - successes for successes, trials in known)
    mean = alpha / (alpha + beta)
    output = []
    for sensor_id, successes, trials in rows:
        if successes is None:
            successes = math.floor(trials * mean + 0.5)
        output.append([sensor_id, str(successes), str(trials)])
    metrics = [
        f"Posterior Alpha: {alpha:.4f}",
        f"Posterior Beta: {beta:.4f}",
        f"Posterior Mean: {mean:.4f}",
    ]
    return output, metrics


def test_program_performs_bayesian_imputation_on_new_inputs():
    binary = rust_binary_name()
    saved = {}
    for path in (INPUT, CLEANED, METRICS):
        saved[path] = path.read_bytes() if path.exists() else None

    try:
        for rows in (make_case(7), make_case(9)):
            with INPUT.open("w", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(["sensor_id", "successes", "trials"])
                for sensor_id, successes, trials in rows:
                    writer.writerow([sensor_id, "" if successes is None else successes, trials])

            CLEANED.unlink(missing_ok=True)
            METRICS.unlink(missing_ok=True)
            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", str(MANIFEST), "--bin", binary],
                cwd=PROJECT,
                text=True,
                capture_output=True,
                timeout=120,
            )
            assert result.returncode == 0, f"The Rust program failed on a valid input:\n{result.stdout}\n{result.stderr}"
            assert CLEANED.is_file(), "Running the Rust program did not create cleaned_data.csv."
            assert METRICS.is_file(), "Running the Rust program did not create metrics.txt."

            expected_rows, expected_metrics = expected_for(rows)
            with CLEANED.open(newline="") as f:
                actual_csv = list(csv.reader(f))
            assert actual_csv == [["sensor_id", "successes", "trials"]] + expected_rows

            actual_metrics = [line.strip() for line in METRICS.read_text().splitlines() if line.strip()]
            assert actual_metrics == expected_metrics
    finally:
        for path, data in saved.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
