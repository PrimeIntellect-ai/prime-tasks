#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import pytest

SANITIZER = "/home/user/sanitizer"


def run_sanitizer(input_data):
    return subprocess.run(
        [SANITIZER],
        input=input_data,
        capture_output=True,
        timeout=10,
    )


def strict_loads(line):
    def reject_constant(value):
        raise ValueError(f"Invalid JSON numeric constant: {value}")
    return json.loads(line, parse_constant=reject_constant)


def is_clean_record(line):
    try:
        value = strict_loads(line)
    except (json.JSONDecodeError, ValueError):
        return False
    if not isinstance(value, dict):
        return False
    rank = value.get("page_rank")
    if isinstance(rank, bool) or not isinstance(rank, (int, float)) or rank < 0:
        return False
    properties = value.get("properties")
    if not isinstance(properties, dict):
        return False
    return not any(isinstance(key, str) and key.startswith("$") for key in properties)


def test_sanitizer_executable():
    sanitizer_path = "/home/user/sanitizer"
    assert os.path.isfile(sanitizer_path), f"Sanitizer executable not found at {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer at {sanitizer_path} is not executable"
    with open(sanitizer_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"


def test_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer"
    assert os.path.isfile(sanitizer_path), "Sanitizer executable not found"

    evil_dir = "/app/evil/"
    clean_dir = "/app/clean/"

    evil_bypassed = []
    clean_modified = []

    evil_files = []
    if os.path.isdir(evil_dir):
        evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
        for ef in evil_files:
            file_path = os.path.join(evil_dir, ef)
            with open(file_path, "rb") as f:
                input_data = f.read()

            result = subprocess.run([sanitizer_path], input=input_data, capture_output=True)
            if result.stdout.strip():
                evil_bypassed.append(ef)

    clean_files = []
    if os.path.isdir(clean_dir):
        clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
        for cf in clean_files:
            file_path = os.path.join(clean_dir, cf)
            with open(file_path, "rb") as f:
                input_data = f.read()

            result = subprocess.run([sanitizer_path], input=input_data, capture_output=True)
            if result.stdout.strip() != input_data.strip():
                clean_modified.append(cf)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_mixed_jsonl_corpus():
    token = secrets.token_hex(16)
    clean_zero = json.dumps({
        "node_id": "generated-zero-" + token,
        "page_rank": 0,
        "cluster_id": "C-" + token[:6],
        "properties": {"safe_" + token[:8]: "value", "count": 3},
    }, separators=(",", ":"), ensure_ascii=False)
    clean_positive = json.dumps({
        "properties": {"label": "generated-" + token, "enabled": True},
        "cluster_id": "generated-cluster-" + token,
        "page_rank": 17.625,
        "node_id": "generated-positive-" + token,
    }, separators=(",", ":"), ensure_ascii=False)
    evil_negative = json.dumps({
        "node_id": "generated-negative-" + token,
        "page_rank": -0.125,
        "cluster_id": "C-X",
        "properties": {"safe": "yes"},
    }, separators=(",", ":"))
    evil_operator = json.dumps({
        "node_id": "generated-operator-" + token,
        "page_rank": 4.5,
        "cluster_id": "C-X",
        "properties": {"$" + token[:10]: {"payload": token}},
    }, separators=(",", ":"))
    evil_non_object = json.dumps([token, 1, 2], separators=(",", ":"))
    evil_malformed = '{"node_id":"' + token + '","page_rank":1,"properties":'

    cases = [
        (evil_negative, False),
        (clean_zero, True),
        (evil_operator, False),
        (evil_non_object, False),
        (clean_positive, True),
        (evil_malformed, False),
    ]
    input_data = ("\n".join(line for line, _ in cases) + "\n").encode("utf-8")
    expected_lines = [line.encode("utf-8") for line, clean in cases if clean]

    result = run_sanitizer(input_data)
    assert result.returncode == 0, f"Sanitizer exited with status {result.returncode}: {result.stderr!r}"
    assert result.stdout.splitlines() == expected_lines, (
        "Sanitizer did not preserve exactly the generated clean records and omit all generated evil records"
    )


def test_raw_export_is_actually_sanitized_and_csv_matches_it():
    raw_path = "/app/raw_graph_export.jsonl"
    assert os.path.isfile(raw_path), f"Missing raw export at {raw_path}"
    with open(raw_path, "rb") as f:
        raw_data = f.read()

    raw_lines = raw_data.decode("utf-8").splitlines()
    expected_clean_lines = [line for line in raw_lines if is_clean_record(line)]

    result = run_sanitizer(raw_data)
    assert result.returncode == 0, f"Sanitizer failed on the raw export: {result.stderr!r}"
    assert result.stdout.decode("utf-8").splitlines() == expected_clean_lines, (
        "Running the sanitizer on the raw export did not produce the records required by the validation rules"
    )

    target_cluster = "C-8842"
    expected_rows = []
    for line in expected_clean_lines:
        record = strict_loads(line)
        if record.get("cluster_id") == target_cluster:
            expected_rows.append(f"{record['node_id']},{record['page_rank']},{record['cluster_id']}")
    expected_rows.sort(key=lambda row: row.split(",", 1)[0])
    expected_csv_lines = ["node_id,page_rank,cluster_id"] + expected_rows

    csv_path = "/home/user/final_target_nodes.csv"
    assert os.path.isfile(csv_path), f"Missing final target nodes CSV at {csv_path}"
    with open(csv_path, "r", encoding="utf-8") as f:
        actual_csv_lines = f.read().splitlines()
    assert actual_csv_lines == expected_csv_lines, (
        "Final CSV does not match the target-cluster records obtained by executing the sanitizer on the raw export"
    )


def test_final_target_nodes():
    csv_path = "/home/user/final_target_nodes.csv"
    assert os.path.isfile(csv_path), f"Missing final target nodes CSV at {csv_path}"

    with open(csv_path, "r", encoding="utf-8") as f:
        content = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    assert len(content) == 3, f"Expected 3 lines in CSV (header + 2 rows), found {len(content)}"
    assert content[0] == "node_id,page_rank,cluster_id", f"Incorrect CSV header: {content[0]}"
    assert content[1] == "n1,0.5,C-8842", f"Expected row 1 to be 'n1,0.5,C-8842', got '{content[1]}'"
    assert content[2] == "n5,0.1,C-8842", f"Expected row 2 to be 'n5,0.1,C-8842', got '{content[2]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
