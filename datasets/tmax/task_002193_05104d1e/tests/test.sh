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

GO_FILE = "/home/user/analyze.go"
CSV_FILE = "/home/user/backups.csv"
JSON_FILE = "/home/user/valid_restore_points.json"
BINARY = "/tmp/analyze_submission"

ORIGINAL_CSV = """id,parent_id,type,size_bytes,status
B01,,FULL,5000,OK
B02,B01,INCREMENTAL,500,OK
B03,B02,INCREMENTAL,250,OK
B04,B03,INCREMENTAL,100,CORRUPT
B05,B04,INCREMENTAL,50,OK
C01,,FULL,4000,CORRUPT
C02,C01,INCREMENTAL,400,OK
D01,,FULL,6000,OK
D02,D01,INCREMENTAL,600,OK
"""

EXPECTED_ORIGINAL = [
    {"id": "B01", "materialized_size": 5000},
    {"id": "B02", "materialized_size": 5500},
    {"id": "B03", "materialized_size": 5750},
    {"id": "D01", "materialized_size": 6000},
    {"id": "D02", "materialized_size": 6600},
]

_built = False


def build_program():
    global _built
    if _built:
        return
    result = subprocess.run(
        ["go", "build", "-o", BINARY, GO_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"Go program failed to compile:\n{result.stdout}{result.stderr}"
    assert os.path.isfile(BINARY), "go build did not produce an executable."
    _built = True


def execute_program(csv_text):
    with open(CSV_FILE, "w", newline="") as f:
        f.write(csv_text)

    if os.path.lexists(JSON_FILE):
        if os.path.isdir(JSON_FILE) and not os.path.islink(JSON_FILE):
            pytest.fail(f"{JSON_FILE} is a directory, not an output file.")
        os.remove(JSON_FILE)

    build_program()
    result = subprocess.run(
        [BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(JSON_FILE), f"Expected output file {JSON_FILE} is missing."
    assert os.path.isfile(JSON_FILE), f"{JSON_FILE} is not a regular file."
    try:
        with open(JSON_FILE, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {JSON_FILE} as JSON: {e}")


def records_to_csv(records):
    from io import StringIO
    stream = StringIO()
    writer = csv.DictWriter(
        stream,
        fieldnames=["id", "parent_id", "type", "size_bytes", "status"],
        lineterminator="\n",
    )
    writer.writeheader()
    writer.writerows(records)
    return stream.getvalue()


def derive_expected(records):
    by_id = {record["id"]: record for record in records}
    memo = {}
    visiting = set()

    def project(backup_id):
        if backup_id in memo:
            return memo[backup_id]
        assert backup_id not in visiting
        visiting.add(backup_id)
        record = by_id[backup_id]
        size = int(record["size_bytes"])

        if record["type"] == "FULL":
            valid = record["status"] == "OK"
            total = size
        else:
            parent_valid, parent_total = project(record["parent_id"])
            valid = record["status"] == "OK" and parent_valid
            total = parent_total + size

        visiting.remove(backup_id)
        memo[backup_id] = (valid, total)
        return memo[backup_id]

    expected = []
    for backup_id in by_id:
        valid, total = project(backup_id)
        if valid:
            expected.append({"id": backup_id, "materialized_size": total})
    return sorted(expected, key=lambda item: item["id"])


def assert_output_shape_and_value(data, expected):
    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert data == expected, f"JSON output does not match expected valid restore points.\nExpected: {expected}\nGot: {data}"

    ids = [item.get("id") if isinstance(item, dict) else None for item in data]
    assert ids == sorted(ids), "The JSON array is not sorted by 'id' in ascending alphabetical order."

    for item in data:
        assert isinstance(item, dict), "Every array item must be a JSON object."
        assert set(item.keys()) == {"id", "materialized_size"}, (
            "Each output object must have exactly the keys 'id' and 'materialized_size'."
        )
        assert isinstance(item["id"], str), "The 'id' value must be a string."
        assert type(item["materialized_size"]) is int, "The 'materialized_size' value must be an integer."


def test_go_file_exists():
    assert os.path.exists(GO_FILE), f"Expected Go source file {GO_FILE} is missing."
    assert os.path.isfile(GO_FILE), f"{GO_FILE} is not a regular file."


def test_json_output_exists_and_correct_after_execution():
    data = execute_program(ORIGINAL_CSV)
    assert_output_shape_and_value(data, EXPECTED_ORIGINAL)


def test_program_projects_unseen_backup_hierarchies():
    for _ in range(3):
        rng = random.Random(secrets.randbits(128))
        token = secrets.token_hex(4).upper()
        ids = [f"{token}_{rng.randrange(100000, 999999)}_{i}" for i in range(12)]
        sizes = [rng.randrange(17, 9001) for _ in ids]

        specs = [
            (0, None, "FULL", "OK"),
            (1, 0, "INCREMENTAL", "OK"),
            (2, 1, "INCREMENTAL", "OK"),
            (3, 1, "INCREMENTAL", "CORRUPT"),
            (4, 3, "INCREMENTAL", "OK"),
            (5, 0, "INCREMENTAL", "OK"),
            (6, None, "FULL", "OK"),
            (7, 6, "INCREMENTAL", "OK"),
            (8, 7, "INCREMENTAL", "CORRUPT"),
            (9, 8, "INCREMENTAL", "OK"),
            (10, None, "FULL", "CORRUPT"),
            (11, 10, "INCREMENTAL", "OK"),
        ]

        records = []
        for index, parent_index, backup_type, status in specs:
            records.append({
                "id": ids[index],
                "parent_id": "" if parent_index is None else ids[parent_index],
                "type": backup_type,
                "size_bytes": str(sizes[index]),
                "status": status,
            })

        expected = derive_expected(records)
        rng.shuffle(records)
        data = execute_program(records_to_csv(records))
        assert_output_shape_and_value(data, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
