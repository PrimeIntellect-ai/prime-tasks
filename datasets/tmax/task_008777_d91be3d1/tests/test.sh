#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import random
import secrets
import subprocess
from collections import defaultdict
import pytest

OUTPUT_PATH = "/home/user/output.json"
INPUT_PATH = "/home/user/raw_events.csv"
PROJECT_PATH = "/home/user/graph_pipeline"
MANIFEST_PATH = os.path.join(PROJECT_PATH, "Cargo.toml")
MAIN_PATH = os.path.join(PROJECT_PATH, "src", "main.rs")


def compute_expected_top_users(input_path=INPUT_PATH):
    """Compute the expected top 5 users directly from an events file."""
    sessions = defaultdict(set)

    with open(input_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_id = row.get("user_id", "").strip()
            session_id = row.get("session_id", "").strip()
            if user_id and session_id:
                sessions[session_id].add(user_id)

    graph = defaultdict(set)
    for users in sessions.values():
        for u1 in users:
            for u2 in users:
                if u1 != u2:
                    graph[u1].add(u2)

    degrees = {u: len(neighbors) for u, neighbors in graph.items()}
    sorted_users = sorted(degrees.items(), key=lambda x: (-x[1], x[0]))
    return [{"user_id": u, "degree": d} for u, d in sorted_users[:5]]


def load_and_validate_output(expected_top_users):
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. The pipeline did not write the output."

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {OUTPUT_PATH} does not contain valid JSON.")

    assert isinstance(data, dict), "The top-level JSON value must be an object."
    assert "schema_version" in data, "JSON output is missing the 'schema_version' key."
    assert data["schema_version"] == "1.0", f"Expected schema_version '1.0', but got {data['schema_version']}."
    assert "top_users" in data, "JSON output is missing the 'top_users' key."
    assert set(data.keys()) == {"schema_version", "top_users"}, "JSON output contains unexpected top-level keys."

    top_users = data["top_users"]
    assert isinstance(top_users, list), "The 'top_users' field must be a list."
    assert len(top_users) == len(expected_top_users), f"Expected {len(expected_top_users)} users in 'top_users', but got {len(top_users)}."

    for i, (actual, expected) in enumerate(zip(top_users, expected_top_users)):
        assert isinstance(actual, dict), f"Element at index {i} in 'top_users' is not a dictionary."
        assert "user_id" in actual, f"Element at index {i} is missing 'user_id'."
        assert "degree" in actual, f"Element at index {i} is missing 'degree'."
        assert set(actual.keys()) == {"user_id", "degree"}, f"Element at index {i} contains unexpected keys."
        assert isinstance(actual["user_id"], str), f"user_id at index {i} must be a string."
        assert isinstance(actual["degree"], int) and not isinstance(actual["degree"], bool), f"degree at index {i} must be an integer."
        assert actual["user_id"] == expected["user_id"], f"Expected user_id '{expected['user_id']}' at rank {i+1}, but got '{actual['user_id']}'."
        assert actual["degree"] == expected["degree"], f"Expected degree {expected['degree']} for user {expected['user_id']}, but got {actual['degree']}."


def run_pipeline():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--offline", "--manifest-path", MANIFEST_PATH],
        cwd=PROJECT_PATH,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust pipeline failed to run via cargo:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), "The executed Rust pipeline did not create /home/user/output.json."


def write_generated_case(case_number):
    token = secrets.token_hex(6)
    users = [f"R{token}_{i:02d}" for i in range(14)]
    sid = lambda n: f"SESSION_{token}_{case_number}_{n}"
    groups = [
        [users[0], users[1], users[2]],
        [users[0], users[3]],
        [users[1], users[3], users[4]],
        [users[5], users[6], users[7], users[8]],
        [users[5], users[9]],
        [users[10], users[11]],
        [users[2], users[5]],
        [users[12], users[13], users[0]],
        [users[4], users[8], users[10]],
    ]
    rows = []
    for index, group in enumerate(groups):
        for user in group:
            rows.append((user, sid(index)))
    rows.extend([rows[0], rows[3], rows[-1]])
    random.SystemRandom().shuffle(rows)

    with open(INPUT_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["user_id", "session_id"])
        writer.writerows(rows)


def test_output_file_exists():
    """Test that the output JSON file has been created."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. The pipeline did not write the output."


def test_output_json_structure_and_values():
    """Test that the output JSON strictly follows the required schema and contains correct values."""
    load_and_validate_output(compute_expected_top_users())


def test_rust_cargo_project_exists():
    assert os.path.isdir(PROJECT_PATH), "Missing Cargo project directory /home/user/graph_pipeline."
    assert os.path.isfile(MANIFEST_PATH), "Missing /home/user/graph_pipeline/Cargo.toml."
    assert os.path.isfile(MAIN_PATH), "Missing Rust entry point /home/user/graph_pipeline/src/main.rs."

    result = subprocess.run(
        ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST_PATH],
        cwd=PROJECT_PATH,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Invalid Cargo project:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    assert metadata.get("packages"), "Cargo project contains no package."
    assert any("bin" in target.get("kind", []) for package in metadata["packages"] for target in package.get("targets", [])), "Cargo project has no Rust binary target."


def test_executed_rust_pipeline_on_derived_inputs():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    try:
        for case_number in range(2):
            write_generated_case(case_number)
            expected = compute_expected_top_users()
            run_pipeline()
            load_and_validate_output(expected)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        run_pipeline()
        load_and_validate_output(compute_expected_top_users())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
