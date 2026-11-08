#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import subprocess

PROJECT = "/home/user/pca_prep"
DATA_PATH = "/home/user/data.csv"
LOG_PATH = "/home/user/experiment_log.json"


def compute_expected_values(data_path=DATA_PATH):
    if not os.path.exists(data_path):
        return 0, 0, 0.0

    with open(data_path, "r") as f:
        reader = csv.reader(f)
        data = [[float(x) for x in row] for row in reader if row]

    rows = len(data)
    cols = len(data[0]) if rows > 0 else 0

    if rows <= 1:
        return rows, cols, 0.0

    trace = 0.0
    for c in range(cols):
        col_data = [data[r][c] for r in range(rows)]
        mean = sum(col_data) / rows
        variance = sum((x - mean) ** 2 for x in col_data) / (rows - 1)
        trace += variance

    return rows, cols, round(trace, 4)


def read_and_validate_log(expected_rows, expected_cols, expected_variance):
    assert os.path.isfile(LOG_PATH), "Output file /home/user/experiment_log.json is missing."

    try:
        with open(LOG_PATH, "r") as f:
            raw = f.read()
        result = json.loads(raw)
    except Exception as e:
        assert False, f"Failed to read or parse /home/user/experiment_log.json: {e}"

    assert "rows" in result, "'rows' key missing in JSON output."
    assert "cols" in result, "'cols' key missing in JSON output."
    assert "total_variance" in result, "'total_variance' key missing in JSON output."

    assert result["rows"] == expected_rows, f"Expected {expected_rows} rows, got {result['rows']}."
    assert result["cols"] == expected_cols, f"Expected {expected_cols} cols, got {result['cols']}."

    agent_variance = result["total_variance"]
    assert isinstance(agent_variance, (int, float)) and not isinstance(agent_variance, bool), \
        "total_variance must be a number."

    diff = abs(float(agent_variance) - expected_variance)
    assert diff <= 0.0001, f"Expected total_variance {expected_variance}, got {agent_variance}."

    matches = re.findall(r'"total_variance"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{4})(?![\d.eE])', raw)
    assert len(matches) == 1, \
        "total_variance must be written as a JSON number with exactly four decimal places."


def cargo_env():
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    if os.path.isdir("/home/user/.cargo"):
        env["CARGO_HOME"] = "/home/user/.cargo"
    return env


def run_rust_program():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    completed = subprocess.run(
        ["/usr/bin/cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        env=cargo_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert completed.returncode == 0, \
        f"Cargo project failed to run:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert os.path.isfile(LOG_PATH), "Running the Rust program did not create experiment_log.json."


def test_pca_prep_exists():
    """Check that a real Cargo binary project exists."""
    assert os.path.isdir(PROJECT), "Rust project directory /home/user/pca_prep is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing."

    completed = subprocess.run(
        ["/usr/bin/cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        env=cargo_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, f"Invalid Cargo project: {completed.stderr}"
    metadata = json.loads(completed.stdout)
    assert metadata.get("packages"), "Cargo project contains no package."
    assert any("bin" in target.get("kind", []) for package in metadata["packages"] for target in package.get("targets", [])), \
        "Cargo project contains no Rust binary target."


def test_experiment_log_exists():
    """Check if the output JSON file exists."""
    assert os.path.isfile(LOG_PATH), "Output file /home/user/experiment_log.json is missing."


def test_experiment_log_content():
    """Validate the contents of the experiment log JSON."""
    read_and_validate_log(*compute_expected_values())


def test_rust_program_executes_and_computes_derived_input():
    """Execute the Cargo project on verifier-generated data, then restore and rerun the real data."""
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    rng = random.SystemRandom()
    generated = [
        [rng.randint(-50000, 50000) / 137.0 + r * 0.013 - c * 0.021 for c in range(5)]
        for r in range(13)
    ]

    try:
        with open(DATA_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerows(generated)

        expected = compute_expected_values()
        run_rust_program()
        read_and_validate_log(*expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)

        # Leave the requested final artifact populated from the original dataset.
        run_rust_program()

    read_and_validate_log(*compute_expected_values())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
