#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess

import numpy as np
import pytest

PROJECT_DIR = "/home/user/signal_analysis"
OUTPUT_FILE = "/home/user/analysis_output.json"
DATA_FILE = "/home/user/sensor_data.csv"


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory {PROJECT_DIR} does not exist."
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        ["cargo", "run", "--release"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=900,
    )
    assert result.returncode == 0, "Rust program failed to compile or run:\n" + result.stdout[-8000:]
    assert os.path.isfile(OUTPUT_FILE), f"Program did not create {OUTPUT_FILE}."


def load_output():
    with open(OUTPUT_FILE, "r") as f:
        return json.load(f)


def load_matrix():
    records = []
    times = set()
    sensors = set()
    with open(DATA_FILE, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["time_idx", "sensor_idx", "reading"]
        for row in reader:
            t = int(row["time_idx"])
            s = int(row["sensor_idx"])
            value = float(row["reading"])
            records.append((t, s, value))
            times.add(t)
            sensors.add(s)

    ordered_times = sorted(times)
    ordered_sensors = sorted(sensors)
    time_pos = {value: i for i, value in enumerate(ordered_times)}
    sensor_pos = {value: i for i, value in enumerate(ordered_sensors)}
    matrix = np.empty((len(ordered_times), len(ordered_sensors)), dtype=np.float64)
    seen = set()
    for t, s, value in records:
        key = (t, s)
        assert key not in seen, f"Duplicate matrix cell {key} in input"
        seen.add(key)
        matrix[time_pos[t], sensor_pos[s]] = value
    assert len(seen) == matrix.size, "Input does not form a complete matrix"
    return matrix


@pytest.fixture(scope="session")
def reference_results():
    matrix = load_matrix()
    u, singular_values, vt = np.linalg.svd(matrix, full_matrices=False)
    reconstructed = (u[:, :3] * singular_values[:3]) @ vt[:3, :]

    edges = np.linspace(-10.0, 10.0, 51)
    original_hist, _ = np.histogram(matrix.ravel(), bins=edges)
    reconstructed_hist, _ = np.histogram(reconstructed.ravel(), bins=edges)
    assert original_hist.sum() > 0 and reconstructed_hist.sum() > 0
    original_prob = original_hist.astype(np.float64) / original_hist.sum()
    reconstructed_prob = reconstructed_hist.astype(np.float64) / reconstructed_hist.sum()
    distance = float(np.linalg.norm(original_prob - reconstructed_prob))

    # This independently exercises the specified row bootstrap. Its RNG is
    # intentionally independent of the submission; a small tolerance accounts
    # for finite-sample quantile variation while still requiring computed CIs.
    rng = np.random.default_rng(42)
    m = matrix.shape[0]
    bootstrap_values = np.empty((1000, 3), dtype=np.float64)
    for iteration in range(1000):
        indices = rng.integers(0, m, size=m)
        bootstrap_values[iteration] = np.linalg.svd(
            matrix[indices, :], compute_uv=False
        )[:3]
    lower = np.percentile(bootstrap_values, 2.5, axis=0)
    upper = np.percentile(bootstrap_values, 97.5, axis=0)

    return {
        "dimensions": list(matrix.shape),
        "singular_values": singular_values[:3],
        "ci_lower": lower,
        "ci_upper": upper,
        "distance": distance,
    }


def test_rust_project_exists():
    """Verify that the Rust project directory and basic files exist."""
    assert os.path.exists(PROJECT_DIR), f"Rust project directory {PROJECT_DIR} does not exist."
    assert os.path.isdir(PROJECT_DIR), f"{PROJECT_DIR} is not a directory."

    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.exists(cargo_toml), f"Cargo.toml not found at {cargo_toml}."

    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.exists(main_rs), f"main.rs not found at {main_rs}."

    with open(cargo_toml, "r") as f:
        cargo_text = f.read().lower()
    assert "nalgebra" in cargo_text, "Cargo.toml must depend on nalgebra."
    assert "rand_chacha" in cargo_text, "Cargo.toml must depend on rand_chacha."

    rust_sources = []
    for root, _, files in os.walk(os.path.join(PROJECT_DIR, "src")):
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r") as f:
                    rust_sources.append(f.read())
    source = "\n".join(rust_sources)
    assert "ChaCha8Rng" in source, "Rust implementation must use ChaCha8Rng."
    assert "seed_from_u64" in source, "Rust implementation must seed its RNG with seed_from_u64."
    assert re.search(r"\b42\b", source), "Rust implementation must use seed 42."
    assert re.search(r"\b1000\b", source), "Rust implementation must perform 1000 bootstrap iterations."


def test_analysis_output_exists_and_valid_json():
    """Verify that the analysis_output.json file exists and is valid JSON."""
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

    try:
        data = load_output()
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")
    assert isinstance(data, dict), "JSON root must be an object (dictionary)."


def test_analysis_output_structure_and_values(reference_results):
    """Verify structure and recompute all requested numerical results."""
    data = load_output()

    assert "matrix_dimensions" in data, "Missing 'matrix_dimensions' key."
    assert data["matrix_dimensions"] == [100, 20], (
        f"Expected matrix_dimensions to be [100, 20], got {data['matrix_dimensions']}."
    )
    assert data["matrix_dimensions"] == reference_results["dimensions"]

    assert "top_3_svd" in data, "Missing 'top_3_svd' key."
    top_3_svd = data["top_3_svd"]
    assert isinstance(top_3_svd, list), "'top_3_svd' should be a list."
    assert len(top_3_svd) == 3, f"Expected 3 items in 'top_3_svd', got {len(top_3_svd)}."

    for i, sv_obj in enumerate(top_3_svd):
        assert isinstance(sv_obj, dict), f"Item {i} in 'top_3_svd' is not an object."
        for key in ["value", "ci_lower", "ci_upper"]:
            assert key in sv_obj, f"Missing '{key}' in 'top_3_svd' item {i}."
            assert isinstance(sv_obj[key], (int, float)), (
                f"'{key}' in 'top_3_svd' item {i} must be a number."
            )
            assert not isinstance(sv_obj[key], bool) and math.isfinite(float(sv_obj[key])), (
                f"'{key}' in 'top_3_svd' item {i} must be finite."
            )

        assert sv_obj["ci_lower"] <= sv_obj["ci_upper"], (
            f"ci_lower > ci_upper for item {i}."
        )
        assert np.isclose(
            sv_obj["value"], reference_results["singular_values"][i], rtol=1e-7, atol=1e-7
        ), f"Singular value {i + 1} was not computed from sensor_data.csv."
        assert np.isclose(
            sv_obj["ci_lower"], reference_results["ci_lower"][i], rtol=0.04, atol=0.5
        ), f"Bootstrap lower confidence bound {i + 1} is incorrect."
        assert np.isclose(
            sv_obj["ci_upper"], reference_results["ci_upper"][i], rtol=0.04, atol=0.5
        ), f"Bootstrap upper confidence bound {i + 1} is incorrect."

    assert "distribution_l2_distance" in data, "Missing 'distribution_l2_distance' key."
    dist = data["distribution_l2_distance"]
    assert isinstance(dist, (int, float)), "'distribution_l2_distance' must be a number."
    assert not isinstance(dist, bool) and math.isfinite(float(dist)), (
        "'distribution_l2_distance' must be finite."
    )
    assert 0.0 <= dist <= 1.0, (
        f"'distribution_l2_distance' {dist} is out of range [0.0, 1.0]."
    )
    assert np.isclose(dist, reference_results["distance"], rtol=1e-7, atol=1e-8), (
        "distribution_l2_distance was not computed from the rank-3 reconstruction."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
