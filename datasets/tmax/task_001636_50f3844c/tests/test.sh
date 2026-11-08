#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import math
import subprocess
import pytest

PROJECT_DIR = "/home/user/retrieval_tool"
CARGO_TOML = os.path.join(PROJECT_DIR, "Cargo.toml")
CSV_PATH = "/home/user/embeddings.csv"
JSON_PATH = "/home/user/top_matches.json"
QUERY = [0.12, 0.88, 0.34, 0.71, 0.55]


def compute_expected(csv_path):
    mag_q = math.sqrt(sum(x * x for x in QUERY))
    results = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row_id = int(row["id"])
            vec = [float(row[f"v{i}"]) for i in range(1, 6)]
            dot = sum(q * v for q, v in zip(QUERY, vec))
            mag_v = math.sqrt(sum(v * v for v in vec))
            sim = 0.0 if mag_v == 0 else dot / (mag_q * mag_v)
            results.append((sim, row_id))
    results.sort(key=lambda x: (-x[0], x[1]))
    return results[:3]


def validate_output(csv_path):
    assert os.path.isfile(JSON_PATH), f"Expected output file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON root must be an array."
    assert len(data) == 3, f"Expected exactly 3 top matches, but got {len(data)}."

    # JSON numeric parsing discards trailing zeroes, so inspect the source text too.
    similarity_tokens = re.findall(r'"similarity"\s*:\s*([^,}\s]+)', raw)
    assert len(similarity_tokens) == 3, "Expected exactly three similarity fields."
    for token in similarity_tokens:
        assert re.fullmatch(r'-?(?:0|[1-9][0-9]*)\.[0-9]{6}', token), (
            f"Similarity value {token!r} is not displayed with exactly 6 decimal places."
        )

    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
    top_3 = compute_expected(csv_path)

    for i in range(3):
        expected_sim, expected_id = top_3[i]
        expected_sim_rounded = round(expected_sim, 6)
        item = data[i]
        assert isinstance(item, dict), f"Object at index {i} must be a JSON object."
        assert "id" in item, f"Object at index {i} is missing the 'id' key."
        assert "similarity" in item, f"Object at index {i} is missing the 'similarity' key."

        actual_id = item["id"]
        actual_sim = item["similarity"]
        assert isinstance(actual_id, int) and not isinstance(actual_id, bool), (
            f"Object at index {i} must contain an integer id."
        )
        assert isinstance(actual_sim, (int, float)) and not isinstance(actual_sim, bool), (
            f"Object at index {i} must contain a numeric similarity."
        )
        assert actual_id == expected_id, (
            f"Rank {i+1} mismatch: expected ID {expected_id}, but got {actual_id}."
        )
        assert math.isclose(actual_sim, expected_sim_rounded, abs_tol=1e-5), (
            f"Rank {i+1} (ID {expected_id}) similarity mismatch: "
            f"expected {expected_sim_rounded}, but got {actual_sim}."
        )


def run_tool():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    proc = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, (
        "The Rust CLI failed to run.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )
    assert os.path.isfile(JSON_PATH), "Running the Rust CLI did not create top_matches.json."


@pytest.fixture(scope="session", autouse=True)
def build_and_exercise_rust_cli():
    assert os.path.isfile(CARGO_TOML), (
        f"Expected a Rust project with a Cargo.toml at {CARGO_TOML}, but it was not found."
    )
    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        "The Rust project did not compile successfully.\n"
        f"stdout:\n{build.stdout}\n"
        f"stderr:\n{build.stderr}"
    )

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        # First verify the requested pipeline on the supplied dataset.
        run_tool()
        validate_output(CSV_PATH)

        # Exercise the compiled implementation on a different dataset so a
        # precomputed or directly fabricated answer cannot pass.
        challenge = """id,v1,v2,v3,v4,v5
42,0.12,0.88,0.34,0.71,0.55
7,0.12,0.88,0.34,0.71,0.55
103,0.13,0.86,0.35,0.70,0.56
2,1.0,0.0,0.0,0.0,0.0
88,0.0,0.0,0.0,0.0,0.0
19,0.3,0.2,0.9,0.1,0.4
61,0.0,1.0,0.0,0.0,0.0
"""
        with open(CSV_PATH, "w") as f:
            f.write(challenge)
        run_tool()
        validate_output(CSV_PATH)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        # Leave the required artifact corresponding to the original input.
        run_tool()


def test_rust_project_exists():
    """Verify that the Rust project was created in the correct directory."""
    assert os.path.isfile(CARGO_TOML), (
        f"Expected a Rust project with a Cargo.toml at {CARGO_TOML}, but it was not found."
    )


def test_top_matches_output():
    """Verify the final JSON contains the correct results for the supplied CSV."""
    validate_output(CSV_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
