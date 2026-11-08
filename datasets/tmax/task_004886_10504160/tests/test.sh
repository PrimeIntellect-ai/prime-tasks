#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import json
import subprocess
import pytest


def test_rust_binary_performance_and_correctness():
    app_dir = "/app/graph-backup-analyzer"
    db_path = "/var/backups/graph_data.db"
    output_path = "/home/user/validation.json"
    golden_path = "/tests/golden_validation.json"

    assert os.path.exists(app_dir), f"Directory {app_dir} does not exist."
    assert os.path.exists(db_path), f"Database {db_path} does not exist."
    assert os.path.exists(golden_path), f"Golden JSON {golden_path} does not exist."

    if os.path.exists(output_path):
        os.remove(output_path)

    start_time = time.time()
    result = subprocess.run(
        ["cargo", "run", "--release", "--", "--db", db_path, "--output", output_path],
        cwd=app_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    end_time = time.time()

    execution_time = end_time - start_time

    assert result.returncode == 0, (
        f"Cargo run failed with code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )

    threshold = 2.0
    assert execution_time <= threshold, (
        f"Execution time {execution_time:.2f}s exceeded the threshold of {threshold}s."
    )

    assert os.path.exists(output_path), f"Output file {output_path} was not generated."

    with open(output_path, "r") as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON.")

    with open(golden_path, "r") as f:
        expected_json = json.load(f)

    def sort_json(data):
        if isinstance(data, list):
            return sorted([sort_json(x) for x in data], key=lambda x: str(x))
        if isinstance(data, dict):
            return {k: sort_json(v) for k, v in data.items()}
        return data

    assert sort_json(actual_json) == sort_json(expected_json), (
        "The generated JSON output does not match the expected golden JSON."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
