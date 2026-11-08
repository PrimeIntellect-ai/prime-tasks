#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/scripts/verify_backups.sh"
NODES_PATH = "/home/user/backups/nodes.jsonl"
EDGES_PATH = "/home/user/backups/edges.csv"
OUTPUT_PATH = "/home/user/output/valid_backup_pairs.jsonl"


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="module", autouse=True)
def execute_on_original_data_and_restore_state():
    with open(NODES_PATH, "rb") as f:
        original_nodes = f.read()
    with open(EDGES_PATH, "rb") as f:
        original_edges = f.read()

    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    run_script()
    baseline_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            baseline_output = f.read()

    yield

    with open(NODES_PATH, "wb") as f:
        f.write(original_nodes)
    with open(EDGES_PATH, "wb") as f:
        f.write(original_edges)
    if baseline_output is None:
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
    else:
        with open(OUTPUT_PATH, "wb") as f:
            f.write(baseline_output)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_output_file_contents():
    expected_pairs = [
        {"database_id": "db_1", "storage_id": "stor_1"},
        {"database_id": "db_3", "storage_id": "stor_2"},
        {"database_id": "db_4", "storage_id": "stor_4"},
    ]

    actual_pairs = []
    with open(OUTPUT_PATH, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                parsed = json.loads(line)
                assert "database_id" in parsed and "storage_id" in parsed, (
                    f"Line {line_num} missing required keys."
                )
                actual_pairs.append(parsed)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {OUTPUT_PATH} is not valid JSON: {line}")

    assert len(actual_pairs) == len(expected_pairs), (
        f"Expected {len(expected_pairs)} output lines, got {len(actual_pairs)}."
    )

    db_ids = [p["database_id"] for p in actual_pairs]
    assert db_ids == sorted(db_ids), "Output is not sorted alphabetically by database_id."
    assert actual_pairs == expected_pairs, (
        f"Output pairs do not match expected. Expected: {expected_pairs}, Got: {actual_pairs}"
    )

    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
        for expected, actual_line in zip(expected_pairs, lines):
            expected_str = (
                f'{{"database_id":"{expected["database_id"]}",'
                f'"storage_id":"{expected["storage_id"]}"}}'
            )
            actual_stripped = actual_line.replace(" ", "")
            expected_stripped = expected_str.replace(" ", "")
            assert actual_stripped == expected_stripped, (
                f"Line format mismatch. Expected roughly {expected_str}, got {actual_line}"
            )


def derive_expected(nodes, edges):
    by_id = {node["id"]: node for node in nodes}
    pairs = []
    for source_id, target_id, relation_type in edges:
        source = by_id.get(source_id)
        target = by_id.get(target_id)
        if relation_type != "STORES_BACKUP_FOR" or source is None or target is None:
            continue
        if source.get("type") != "StorageNode" or target.get("type") != "Database":
            continue
        if source.get("status") != "ONLINE" or target.get("status") != "ONLINE":
            continue
        pairs.append({"database_id": target_id, "storage_id": source_id})
    return sorted(pairs, key=lambda pair: pair["database_id"])


def assert_current_output(expected):
    assert os.path.isfile(OUTPUT_PATH), f"Script did not create {OUTPUT_PATH}."
    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    actual = []
    for line_num, line in enumerate(lines, 1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Dynamic output line {line_num} is not valid JSON: {line}: {exc}")
        assert set(value.keys()) == {"database_id", "storage_id"}, (
            f"Dynamic output line {line_num} has incorrect keys: {value}"
        )
        actual.append(value)

    assert [pair["database_id"] for pair in actual] == sorted(
        pair["database_id"] for pair in actual
    ), "Dynamic output is not sorted alphabetically by database_id."
    assert actual == expected, f"Expected dynamically derived pairs {expected}, got {actual}."

    assert len(lines) == len(expected)
    for line, pair in zip(lines, expected):
        expected_line = (
            f'{{"database_id":"{pair["database_id"]}",'
            f'"storage_id":"{pair["storage_id"]}"}}'
        )
        assert line.replace(" ", "") == expected_line, (
            f"Line format mismatch. Expected roughly {expected_line}, got {line}"
        )


def test_script_aggregates_from_current_nodes_and_edges():
    for _ in range(2):
        token = secrets.token_hex(5)
        db_a = f"db_a_{token}"
        db_m = f"db_m_{token}"
        db_z = f"db_z_{token}"
        stor_a = f"stor_a_{token}"
        stor_m = f"stor_m_{token}"
        stor_z = f"stor_z_{token}"
        other = f"other_{token}"

        nodes = [
            {"id": db_a, "type": "Database", "status": "ONLINE"},
            {"id": db_m, "type": "Database", "status": "OFFLINE"},
            {"id": db_z, "type": "Database", "status": "ONLINE"},
            {"id": stor_a, "type": "StorageNode", "status": "ONLINE"},
            {"id": stor_m, "type": "StorageNode", "status": "OFFLINE"},
            {"id": stor_z, "type": "StorageNode", "status": "ONLINE"},
            {"id": other, "type": "Application", "status": "ONLINE"},
        ]
        edges = [
            (stor_z, db_z, "STORES_BACKUP_FOR"),
            (stor_a, db_a, "STORES_BACKUP_FOR"),
            (stor_a, db_m, "STORES_BACKUP_FOR"),
            (stor_m, db_a, "STORES_BACKUP_FOR"),
            (db_a, stor_a, "STORES_BACKUP_FOR"),
            (stor_z, db_a, "BACKED_UP_TO"),
            (other, db_a, "STORES_BACKUP_FOR"),
            (stor_a, other, "STORES_BACKUP_FOR"),
            (f"missing_source_{token}", db_a, "STORES_BACKUP_FOR"),
            (stor_a, f"missing_target_{token}", "STORES_BACKUP_FOR"),
        ]
        random.SystemRandom().shuffle(nodes)
        random.SystemRandom().shuffle(edges)
        expected = derive_expected(nodes, edges)

        with open(NODES_PATH, "w") as f:
            for node in nodes:
                f.write(json.dumps(node) + "\n")
        with open(EDGES_PATH, "w") as f:
            f.write("source_id,target_id,relation_type\n")
            for source_id, target_id, relation_type in edges:
                f.write(f"{source_id},{target_id},{relation_type}\n")

        run_script()
        assert_current_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    printf '1\n' > /logs/verifier/reward.txt
else
    printf '0\n' > /logs/verifier/reward.txt
fi
