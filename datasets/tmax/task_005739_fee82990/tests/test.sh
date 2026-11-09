#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys
from collections import defaultdict

import pytest

INPUT_PATH = "/home/user/audit_logs.jsonl"
OUTPUT_PATH = "/home/user/projected_graph.json"
SCRIPT_PATH = "/home/user/audit_graph.py"


def derive_expected(input_path, page, page_size):
    edge_weights = defaultdict(int)
    with open(input_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            sender = record.get("sender")
            recipient = record.get("recipient")
            if sender and recipient:
                edge_weights[(sender, recipient)] += 1

    filtered_edges = [
        {"source": src, "target": tgt, "weight": weight}
        for (src, tgt), weight in edge_weights.items()
        if weight >= 3
    ]
    sorted_edges = sorted(
        filtered_edges,
        key=lambda x: (-x["weight"], x["source"], x["target"]),
    )
    start_idx = (page - 1) * page_size
    return sorted_edges[start_idx:start_idx + page_size]


def validate_output(expected_output):
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    with open(OUTPUT_PATH, "r") as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(actual_output, list), "Output must be a JSON array."
    assert len(actual_output) == len(expected_output), \
        f"Expected {len(expected_output)} items, got {len(actual_output)}."

    for i, actual_item in enumerate(actual_output):
        expected_item = expected_output[i]
        assert isinstance(actual_item, dict), f"Item at index {i} must be an object."
        assert set(actual_item.keys()) == {"source", "target", "weight"}, \
            f"Item at index {i} has incorrect keys: {list(actual_item.keys())}"
        assert isinstance(actual_item["source"], str), \
            f"Item {i} 'source' must be a string."
        assert isinstance(actual_item["target"], str), \
            f"Item {i} 'target' must be a string."
        assert isinstance(actual_item["weight"], int), \
            f"Item {i} 'weight' must be an integer."
        assert actual_item == expected_item, \
            f"Item at index {i} does not match expected.\nExpected: {expected_item}\nActual: {actual_item}"


def run_script(page, page_size):
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, "--page", str(page), "--page-size", str(page_size)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"Script failed for --page {page} --page-size {page_size}:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), \
        f"Script did not create {OUTPUT_PATH} for --page {page} --page-size {page_size}."


def test_01_audit_graph_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."


def test_02_projected_graph_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."


def test_03_submitted_projected_graph_content():
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    expected_output = derive_expected(INPUT_PATH, 2, 2)
    validate_output(expected_output)


def test_04_script_recomputes_and_honors_pagination_arguments():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    records = []
    msg_id = 1
    for source, target, count in [
        ("zeta@test.invalid", "alpha@test.invalid", 6),
        ("alpha@test.invalid", "zeta@test.invalid", 5),
        ("alpha@test.invalid", "beta@test.invalid", 5),
        ("beta@test.invalid", "alpha@test.invalid", 4),
        ("charlie@test.invalid", "delta@test.invalid", 3),
        ("delta@test.invalid", "charlie@test.invalid", 3),
        ("ignored@test.invalid", "small@test.invalid", 2),
    ]:
        for _ in range(count):
            records.append({
                "msg_id": str(msg_id),
                "sender": source,
                "recipient": target,
                "timestamp": 1700000000 + msg_id,
                "has_attachment": False,
            })
            msg_id += 1

    try:
        with open(INPUT_PATH, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        for page, page_size in [(1, 3), (2, 2), (3, 2)]:
            expected_output = derive_expected(INPUT_PATH, page, page_size)
            run_script(page, page_size)
            validate_output(expected_output)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        run_script(2, 2)


def test_05_required_report_after_execution():
    expected_output = derive_expected(INPUT_PATH, 2, 2)
    validate_output(expected_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
