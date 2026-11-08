#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import json
import math
import os
import re
import subprocess

import numpy as np

PROJECT = "/home/user/project/dim_reducer"
CARGO_TOML = os.path.join(PROJECT, "Cargo.toml")
INPUT_CSV = "/home/user/data/embeddings.csv"
OUTPUT_CSV = "/home/user/data/reduced.csv"
LOG_JSON = "/home/user/experiment_log.json"


def run_submission():
    assert os.path.isfile(CARGO_TOML), (
        f"Rust project 'dim_reducer' not found. Expected {CARGO_TOML} to exist."
    )

    # Ensure the checked artifacts are produced by this execution, rather than
    # being stale files prepared independently of the Rust program.
    for path in (OUTPUT_CSV, LOG_JSON):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["RUSTUP_HOME"] = "/opt/rust"
    env["CARGO_HOME"] = "/opt/cargo"
    env["PATH"] = "/opt/cargo/bin:" + env.get("PATH", "")
    result = subprocess.run(
        ["/opt/cargo/bin/cargo", "run", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    assert result.returncode == 0, (
        "The dim_reducer Rust program did not execute successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


run_submission()


def test_rust_project_exists_and_uses_required_crates():
    assert os.path.isfile(CARGO_TOML), f"Rust project 'dim_reducer' not found. Expected {CARGO_TOML} to exist."
    with open(CARGO_TOML, "r", encoding="utf-8") as f:
        manifest = f.read()

    for dependency in ("linfa", "linfa-pca", "ndarray", "csv"):
        pattern = rf"(?m)^\s*{re.escape(dependency)}\s*="
        assert re.search(pattern, manifest), f"Cargo.toml is missing the required dependency {dependency!r}."

    rust_sources = []
    src_dir = os.path.join(PROJECT, "src")
    for root, _, files in os.walk(src_dir):
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r", encoding="utf-8") as f:
                    rust_sources.append(f.read())
    source = "\n".join(rust_sources)
    assert source, "No Rust source files were found in the project's src directory."
    for crate_token in ("linfa", "linfa_pca", "ndarray", "csv"):
        assert re.search(rf"\b{crate_token}\b", source), f"Rust source does not use the required {crate_token} crate."


def test_reduced_csv_valid_and_is_pca_transform():
    assert os.path.isfile(OUTPUT_CSV), f"File {OUTPUT_CSV} is missing."

    with open(OUTPUT_CSV, "r", encoding="utf-8") as f:
        rows = list(csv.reader(f))

    assert len(rows) == 1000, f"Expected 1000 rows in reduced.csv, found {len(rows)}."
    for i, row in enumerate(rows):
        assert len(row) == 5, f"Expected 5 columns in row {i}, found {len(row)}."
        for val in row:
            try:
                f_val = float(val)
                assert not math.isnan(f_val), f"NaN value found in row {i}."
                assert math.isfinite(f_val), f"Non-finite value found in row {i}."
            except ValueError:
                assert False, f"Non-float value found in row {i}: {val}"

    actual = np.asarray(rows, dtype=np.float64)
    source = np.loadtxt(INPUT_CSV, delimiter=",")
    assert source.shape == (1000, 50), f"Expected embeddings.csv to have shape (1000, 50), got {source.shape}."

    # The setup dataset is deterministic. Reject attempts to replace it with an
    # easier input before producing reduced.csv.
    expected_input = np.random.RandomState(42).rand(1000, 50)
    assert np.array_equal(source, expected_input), "embeddings.csv was modified from the supplied dataset."

    centered = source - source.mean(axis=0)
    covariance = centered.T @ centered / (source.shape[0] - 1)
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    order = np.argsort(eigenvalues)[::-1][:5]
    expected = centered @ eigenvectors[:, order]

    # PCA component signs and ordering are not unique, so accept every
    # permutation and independently choose the sign of each component.
    best_error = float("inf")
    matched = False
    for permutation in itertools.permutations(range(5)):
        candidate = actual[:, permutation].copy()
        for j in range(5):
            if np.dot(candidate[:, j], expected[:, j]) < 0:
                candidate[:, j] *= -1
        error = float(np.max(np.abs(candidate - expected)))
        best_error = min(best_error, error)
        if np.allclose(candidate, expected, rtol=2e-4, atol=2e-5):
            matched = True
            break

    assert matched, (
        "reduced.csv is not the 5-component PCA transform of embeddings.csv "
        f"(best maximum absolute error: {best_error})."
    )


def test_experiment_log_valid():
    assert os.path.isfile(LOG_JSON), f"File {LOG_JSON} is missing."

    with open(LOG_JSON, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{LOG_JSON} is not a valid JSON file."

    assert data.get("input_dim") == 50, f"Expected input_dim to be 50, got {data.get('input_dim')}."
    assert data.get("output_dim") == 5, f"Expected output_dim to be 5, got {data.get('output_dim')}."
    assert data.get("status") == "success", f"Expected status to be 'success', got {data.get('status')}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
