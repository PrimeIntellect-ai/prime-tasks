#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess

import pytest

OUTPUT = "/home/user/experiments/recovered_lineage.json"
RAW = "/home/user/experiments/raw_features.csv"
TARGETS = "/home/user/experiments/target_embeddings.json"
PROJECT = "/home/user/tracker"


def test_recovered_lineage_file_exists():
    """Check if the recovered_lineage.json file was generated."""
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} is missing. The Rust program may not have been run or failed to output to the correct path."


def test_recovered_lineage_content():
    """Check if the recovered_lineage.json contains the correct matches in the correct order."""
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} is missing."

    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT} does not contain valid JSON.")

    expected_data = [
        {"id": "data_1", "artifact_id": "artifact_alpha"},
        {"id": "data_2", "artifact_id": "artifact_beta"},
        {"id": "data_3", "artifact_id": "artifact_gamma"},
    ]

    assert isinstance(data, list), f"Expected the root JSON element to be a list, but got {type(data).__name__}."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the JSON array, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary."
        assert "id" in actual, f"Item at index {i} is missing the 'id' key."
        assert "artifact_id" in actual, f"Item at index {i} is missing the 'artifact_id' key."
        assert actual["id"] == expected["id"], f"Expected id '{expected['id']}' at index {i}, but got '{actual['id']}'."
        assert actual["artifact_id"] == expected["artifact_id"], f"Expected artifact_id '{expected['artifact_id']}' for id '{actual['id']}', but got '{actual['artifact_id']}'."


def test_rust_project_exists():
    assert os.path.isdir(PROJECT), f"Expected Rust project directory {PROJECT} is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing from the Rust project."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing from the Rust project."


def derive_expected(rows, targets):
    expected = []
    for row in rows:
        f1, f2, f3, f4 = row["features"]
        feat_a = f1 + f2
        feat_b = f3 * f4
        embedding = [(feat_a * 0.5) + (f1 * 0.2), (feat_b * 0.3) - (f4 * 0.1)]
        artifact_id = min(
            targets,
            key=lambda name: (embedding[0] - targets[name][0]) ** 2
            + (embedding[1] - targets[name][1]) ** 2,
        )
        expected.append({"id": row["id"], "artifact_id": artifact_id})
    return expected


def write_case(rows, targets):
    with open(RAW, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "f1", "f2", "f3", "f4"])
        for row in rows:
            writer.writerow([row["id"], *row["features"]])
    with open(TARGETS, "w") as f:
        json.dump(targets, f)


def assert_generated_output(expected):
    assert os.path.isfile(OUTPUT), "The Rust program did not generate recovered_lineage.json."
    try:
        with open(OUTPUT) as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The Rust program generated invalid JSON: {exc}")
    assert isinstance(actual, list), "Generated lineage must be a JSON array."
    assert len(actual) == len(expected), "Generated lineage has the wrong number of rows."
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(got, dict), f"Generated item {index} is not an object."
        assert "id" in got, f"Generated item {index} is missing 'id'."
        assert "artifact_id" in got, f"Generated item {index} is missing 'artifact_id'."
        assert got["id"] == wanted["id"], f"Wrong row id or row order at index {index}."
        assert got["artifact_id"] == wanted["artifact_id"], f"Wrong nearest artifact for {wanted['id']}."


def test_rust_program_recomputes_lineage_for_new_inputs():
    rng = random.SystemRandom()
    cargo_env = os.environ.copy()
    cargo_env["HOME"] = "/home/user"
    cargo_env["CARGO_HOME"] = "/home/user/.cargo"

    for round_number in range(2):
        rows = []
        targets = {}
        generated = []

        for i in range(5):
            base = 1.0 + i * 2.5
            features = [
                round(base + rng.uniform(0.11, 0.79), 6),
                round(0.4 + rng.uniform(0.07, 1.13), 6),
                round(0.8 + i * 0.9 + rng.uniform(0.05, 0.45), 6),
                round(0.7 + i * 0.6 + rng.uniform(0.09, 0.39), 6),
            ]
            row_id = f"case_{round_number}_{i}_{secrets.token_hex(4)}"
            rows.append({"id": row_id, "features": features})
            f1, f2, f3, f4 = features
            generated.append([(f1 + f2) * 0.5 + f1 * 0.2, (f3 * f4) * 0.3 - f4 * 0.1])

        entries = []
        for i, embedding in enumerate(generated):
            entries.append((f"artifact_{secrets.token_hex(8)}", embedding))
        for i in range(7):
            entries.append((f"distractor_{secrets.token_hex(8)}", [50.0 + i * 3.1, -40.0 - i * 2.7]))
        rng.shuffle(entries)
        targets.update(entries)

        expected = derive_expected(rows, targets)
        write_case(rows, targets)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
            cwd=PROJECT,
            env=cargo_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust program failed on generated inputs:\n{result.stderr}"
        assert_generated_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
