#!/bin/bash
mkdir -p /logs/verifier

MAPPING_CSV_PATH="/home/user/data/authors_papers.csv"
MAPPING_BACKUP="$(mktemp)"
cp "$MAPPING_CSV_PATH" "$MAPPING_BACKUP"

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import secrets
import subprocess
import pytest

PROJECT_PATH = "/home/user/graph_exporter"
SOURCE_PATH = "/home/user/graph_exporter/src/main.rs"
OUTPUT_JSON_PATH = "/home/user/graph_exporter/output.json"
MAPPING_CSV_PATH = "/home/user/data/authors_papers.csv"
EXPECTED_QUERY = "UNWIND $batch AS row MERGE (a:Author {id: row.author_id}) MERGE (p:Paper {id: row.paper_id}) MERGE (a)-[:WROTE]->(p)"

def test_00_run_rust_program_on_fresh_mapping():
    """Run the submitted src/main.rs against a fresh valid mapping."""
    assert os.path.isfile(SOURCE_PATH), f"The Rust source file {SOURCE_PATH} is missing."

    # Use a fresh set of relationships so a precomputed output.json cannot pass.
    pairs = [(author_id, paper_id)
             for author_id in (1, 2, 3)
             for paper_id in (101, 102, 103)]
    secrets.SystemRandom().shuffle(pairs)
    pairs = pairs[:5]
    with open(MAPPING_CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["author_id", "paper_id"])
        writer.writerows(pairs)

    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, (
        "The Rust project metadata could not be read:\n" + metadata_result.stderr
    )
    metadata = json.loads(metadata_result.stdout)
    expected_source = os.path.realpath(SOURCE_PATH)
    targets = [
        target
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", [])
        and os.path.realpath(target.get("src_path", "")) == expected_source
    ]
    assert targets, "Cargo does not define src/main.rs as a binary target."

    run_result = subprocess.run(
        ["cargo", "run", "--quiet", "--bin", targets[0]["name"]],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert run_result.returncode == 0, (
        "Running the Rust program failed:\n" + run_result.stderr
    )

def test_output_json_exists():
    """Verify that the expected output JSON file has been created."""
    assert os.path.isfile(OUTPUT_JSON_PATH), f"The output file {OUTPUT_JSON_PATH} was not found. Did you run the Rust program?"

def test_output_json_structure_and_query():
    """Verify the JSON structure and the exact Cypher query string."""
    with open(OUTPUT_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_JSON_PATH} does not contain valid JSON.")

    assert "query" in data, "The JSON is missing the 'query' key."
    assert "parameters" in data, "The JSON is missing the 'parameters' key."
    assert data["query"] == EXPECTED_QUERY, f"The query string does not match the expected value.\nExpected: {EXPECTED_QUERY}\nActual: {data['query']}"
    assert "batch" in data["parameters"], "The 'parameters' object is missing the 'batch' key."

def test_output_json_batch_data():
    """Verify that the batch data matches the authors_papers.csv mapping exactly."""
    # Read the expected data from the CSV
    expected_batch = []
    assert os.path.isfile(MAPPING_CSV_PATH), f"The mapping file {MAPPING_CSV_PATH} is missing."

    with open(MAPPING_CSV_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            expected_batch.append({
                "author_id": int(row["author_id"]),
                "paper_id": int(row["paper_id"])
            })

    # Sort expected batch
    expected_batch.sort(key=lambda x: (x["author_id"], x["paper_id"]))

    # Read the actual data from the JSON
    with open(OUTPUT_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Invalid JSON in output file.")

    actual_batch = data.get("parameters", {}).get("batch", [])
    assert isinstance(actual_batch, list), "The 'batch' value should be a list."

    # Ensure all items have integer IDs
    for item in actual_batch:
        assert isinstance(item.get("author_id"), int), "author_id in batch must be an integer."
        assert isinstance(item.get("paper_id"), int), "paper_id in batch must be an integer."

    # Sort actual batch just in case, though the instructions said to sort it
    actual_batch_sorted = sorted(actual_batch, key=lambda x: (x.get("author_id", 0), x.get("paper_id", 0)))

    assert actual_batch_sorted == expected_batch, "The batch parameters do not match the expected relationships from the CSV."
    assert actual_batch == actual_batch_sorted, "The batch array in the JSON is not sorted by author_id ascending, then paper_id ascending."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    REWARD=1
else
    REWARD=0
fi

cp "$MAPPING_BACKUP" "$MAPPING_CSV_PATH" 2>/dev/null || true
rm -f "$MAPPING_BACKUP"
echo "$REWARD" > /logs/verifier/reward.txt
