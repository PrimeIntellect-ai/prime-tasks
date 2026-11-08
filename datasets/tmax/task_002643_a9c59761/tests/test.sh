#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import stat
import subprocess
import pytest

PROJECT_DIR = "/home/user/sensor_pipeline"
SCRIPT_PATH = "/home/user/run_pipeline.sh"
OUT_PATH = "/home/user/data/classified_results.csv"
BINARY_PATH = "/home/user/sensor_pipeline/target/release/sensor_pipeline"
RAW_PATH = "/home/user/data/raw_sensor.csv"
WEIGHTS_PATH = "/home/user/data/model_weights.json"


def test_rust_project_exists():
    cargo_toml = "/home/user/sensor_pipeline/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"{cargo_toml} is missing. Did you create the Cargo project?"


def test_run_script_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_run_script_builds_and_runs_rust_pipeline():
    if os.path.exists(OUT_PATH):
        os.remove(OUT_PATH)
    if os.path.exists(BINARY_PATH):
        os.remove(BINARY_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}"
    assert os.path.isfile(OUT_PATH), "run_pipeline.sh did not produce classified_results.csv."
    assert os.path.isfile(BINARY_PATH), "run_pipeline.sh did not build the release sensor_pipeline binary."
    assert os.access(BINARY_PATH, os.X_OK), "The release sensor_pipeline binary is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not a native compiled executable."


def test_classified_results_correct():
    out_path = "/home/user/data/classified_results.csv"
    assert os.path.isfile(out_path), f"{out_path} is missing. Did the pipeline run correctly?"

    # Recompute expected truth
    weights_path = "/home/user/data/model_weights.json"
    raw_data_path = "/home/user/data/raw_sensor.csv"

    assert os.path.isfile(weights_path), f"Input file {weights_path} missing."
    assert os.path.isfile(raw_data_path), f"Input file {raw_data_path} missing."

    with open(weights_path, 'r') as f:
        W = json.load(f)

    expected_rows = []
    with open(raw_data_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            id_val = int(row[0])
            X = [float(x) for x in row[1:]]

            # Dimensionality reduction: Z = X * W
            Z = [0.0, 0.0]
            for i in range(10):
                Z[0] += X[i] * W[i][0]
                Z[1] += X[i] * W[i][1]

            # Log-likelihood calculations
            ll_0 = -0.5 * ((Z[0] - 0.0)**2 + (Z[1] - 0.0)**2)
            ll_1 = -0.5 * ((Z[0] - 2.0)**2 + (Z[1] - (-2.0))**2)

            assigned_class = 0 if ll_0 > ll_1 else 1
            max_ll = max(ll_0, ll_1)

            expected_rows.append([str(id_val), str(assigned_class), f"{max_ll:.4f}"])

    # Read actual results
    with open(out_path, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("The classified_results.csv file is empty.")

        assert header == ["id", "class", "max_ll"], f"Header mismatch: expected ['id', 'class', 'max_ll'], got {header}"

        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows of data, got {len(actual_rows)}."

    for i, (act, exp) in enumerate(zip(actual_rows, expected_rows)):
        assert act == exp, f"Row {i+1} mismatch: expected {exp}, got {act}. Ensure max_ll is rounded to 4 decimal places."


def _expected_for(raw_rows, weights):
    expected = []
    for row in raw_rows:
        id_val = int(row[0])
        x = [float(v) for v in row[1:]]
        z0 = sum(x[i] * weights[i][0] for i in range(10))
        z1 = sum(x[i] * weights[i][1] for i in range(10))
        ll_0 = -0.5 * (z0 ** 2 + z1 ** 2)
        ll_1 = -0.5 * ((z0 - 2.0) ** 2 + (z1 + 2.0) ** 2)
        assigned_class = 0 if ll_0 > ll_1 else 1
        expected.append([str(id_val), str(assigned_class), f"{max(ll_0, ll_1):.4f}"])
    return expected


def test_compiled_rust_binary_processes_changed_inputs():
    original_raw = open(RAW_PATH, "rb").read()
    original_weights = open(WEIGHTS_PATH, "rb").read()

    weights = [
        [1.0, 0.0],
        [0.0, 1.0],
        [0.25, -0.5],
        [0.0, 0.0],
        [0.0, 0.0],
        [0.0, 0.0],
        [0.0, 0.0],
        [0.0, 0.0],
        [0.0, 0.0],
        [0.0, 0.0],
    ]
    raw_rows = [
        [101, 0.31, 0.17, 0.13, 0, 0, 0, 0, 0, 0, 0],
        [205, 2.10, -1.50, 0.37, 0, 0, 0, 0, 0, 0, 0],
        [309, -1.13, 0.83, -0.22, 0, 0, 0, 0, 0, 0, 0],
        [412, 1.70, -0.10, 0.19, 0, 0, 0, 0, 0, 0, 0],
    ]

    try:
        with open(WEIGHTS_PATH, "w") as f:
            json.dump(weights, f)
        with open(RAW_PATH, "w", newline="") as f:
            csv.writer(f, lineterminator="\n").writerows(raw_rows)
        if os.path.exists(OUT_PATH):
            os.remove(OUT_PATH)

        result = subprocess.run(
            [BINARY_PATH],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Compiled Rust binary failed on changed inputs:\n{result.stdout}"
        assert os.path.isfile(OUT_PATH), "Compiled Rust binary did not create classified_results.csv."

        with open(OUT_PATH, newline="") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            actual = list(reader)

        assert header == ["id", "class", "max_ll"]
        assert actual == _expected_for(raw_rows, weights), "Compiled Rust binary produced incorrect results for changed inputs."
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        with open(WEIGHTS_PATH, "wb") as f:
            f.write(original_weights)
        if os.path.exists(OUT_PATH):
            os.remove(OUT_PATH)
        subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=240,
            check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
