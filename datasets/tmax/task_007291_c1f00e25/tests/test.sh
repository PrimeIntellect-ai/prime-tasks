#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess

import pytest

PROJECT = "/home/user/gc_estimator"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
READS = "/home/user/data/reads.csv"
OUTPUT = "/home/user/gc_distribution.json"


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust pipeline failed to run.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Running the Rust project did not create {OUTPUT}."


def load_output():
    with open(OUTPUT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT} is not valid JSON.")


def assert_distribution(expected_mean, expected_std_dev):
    data = load_output()
    assert "mean" in data, "JSON output is missing the 'mean' key."
    assert "std_dev" in data, "JSON output is missing the 'std_dev' key."

    actual_mean = data["mean"]
    actual_std_dev = data["std_dev"]

    assert isinstance(actual_mean, float), "'mean' must be a float."
    assert isinstance(actual_std_dev, float), "'std_dev' must be a float."
    assert math.isclose(actual_mean, expected_mean, rel_tol=1e-7, abs_tol=1e-9), \
        f"Expected mean to be close to {expected_mean}, but got {actual_mean}."
    assert math.isclose(actual_std_dev, expected_std_dev, rel_tol=1e-7, abs_tol=1e-9), \
        f"Expected std_dev to be close to {expected_std_dev}, but got {actual_std_dev}."


def expected_from_csv(path):
    fractions = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            sequence = row["sequence"]
            upper = sequence.upper()
            if sequence and all(ch in "ACGT" for ch in upper):
                fractions.append(sum(ch in "GC" for ch in upper) / len(upper))
    assert fractions, "Verifier generated no valid sequences."
    mean = sum(fractions) / len(fractions)
    variance = sum((value - mean) ** 2 for value in fractions) / len(fractions)
    return mean, math.sqrt(variance)


def test_rust_project_created():
    """Verify that the Rust project was created using Cargo."""
    assert os.path.isfile(MANIFEST), f"Rust project configuration {MANIFEST} does not exist. Did you create the project?"

    rust_sources = []
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if d != "target"]
        rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
    assert rust_sources, "The Cargo project contains no Rust source files."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Cargo could not load the project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    packages = [p for p in metadata["packages"] if os.path.samefile(p["manifest_path"], MANIFEST)]
    assert packages and packages[0]["name"] == "gc_estimator", "The Cargo package must be named gc_estimator."
    binary_targets = [t for t in packages[0]["targets"] if "bin" in t["kind"]]
    assert binary_targets, "The Cargo project does not define a runnable Rust binary."
    assert all(os.path.isfile(t["src_path"]) for t in binary_targets), "A declared Rust binary source file is missing."

    build_result = subprocess.run(
        ["cargo", "build", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build_result.returncode == 0, f"The Rust project does not compile:\n{build_result.stderr}"


def test_json_output_exists():
    """Verify that the output JSON file exists."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."


def test_json_output_content():
    """Verify that the existing JSON output contains the correct mean and std_dev."""
    data = load_output()
    assert "mean" in data, "JSON output is missing the 'mean' key."
    assert "std_dev" in data, "JSON output is missing the 'std_dev' key."

    expected_mean = 3 / 7
    expected_variance = (0 + (4/7)**2 + (-3/7)**2 + (-1/7)**2) / 4
    expected_std_dev = math.sqrt(expected_variance)

    actual_mean = data["mean"]
    actual_std_dev = data["std_dev"]
    assert isinstance(actual_mean, float), "'mean' must be a float."
    assert isinstance(actual_std_dev, float), "'std_dev' must be a float."
    assert math.isclose(actual_mean, expected_mean, rel_tol=1e-7, abs_tol=1e-9), \
        f"Expected mean to be close to {expected_mean}, but got {actual_mean}."
    assert math.isclose(actual_std_dev, expected_std_dev, rel_tol=1e-7, abs_tol=1e-9), \
        f"Expected std_dev to be close to {expected_std_dev}, but got {actual_std_dev}."


def test_pipeline_executes_on_original_data():
    """Build and execute the submitted artifact against the required input."""
    run_pipeline()
    expected_mean = 3 / 7
    expected_variance = (0 + (4/7)**2 + (-3/7)**2 + (-1/7)**2) / 4
    assert_distribution(expected_mean, math.sqrt(expected_variance))


def test_pipeline_computes_from_changed_input():
    """Ensure results are computed from reads.csv rather than hardcoded."""
    with open(READS, "rb") as f:
        original_reads = f.read()

    rng = random.SystemRandom()
    rows = []
    for index, length in enumerate((5, 7, 8, 11, 13, 16)):
        gc_count = rng.randrange(1, length)
        sequence = [rng.choice("GC") for _ in range(gc_count)]
        sequence += [rng.choice("AT") for _ in range(length - gc_count)]
        rng.shuffle(sequence)
        sequence = "".join(ch.lower() if rng.randrange(2) else ch for ch in sequence)
        rows.append((f"valid_{index}", sequence))
    rows.extend([
        ("bad_x", "ACGTXACGT"),
        ("bad_n", "NNNN"),
        ("bad_digit", "GC12AT"),
        ("bad_dash", "AC-GT"),
    ])

    try:
        with open(READS, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "sequence"])
            writer.writerows(rows)
        expected_mean, expected_std_dev = expected_from_csv(READS)
        run_pipeline()
        assert_distribution(expected_mean, expected_std_dev)
    finally:
        with open(READS, "wb") as f:
            f.write(original_reads)

    run_pipeline()
    expected_mean = 3 / 7
    expected_variance = (0 + (4/7)**2 + (-3/7)**2 + (-1/7)**2) / 4
    assert_distribution(expected_mean, math.sqrt(expected_variance))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
