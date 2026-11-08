#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

SOURCE = "/home/user/process_backups.c"
CSV_PATH = "/home/user/backups.csv"
JSON_PATH = "/home/user/valid_backups.json"
BINARY = "/tmp/process_backups_verifier"
EXPECTED_QUERY = "INSERT INTO restored_backups (id, ts, db, bytes) VALUES (?, ?, ?, ?);"


def compile_and_run():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "process_backups.c did not compile successfully:\n" + compile_result.stderr
    )

    run_result = subprocess.run(
        [BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert run_result.returncode == 0, (
        "The compiled process_backups program exited unsuccessfully:\n" + run_result.stderr
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SOURCE), "The C program /home/user/process_backups.c is missing."
    compile_and_run()
    yield


def test_c_program_exists():
    """Test that the C program was created."""
    assert os.path.isfile(SOURCE), "The C program /home/user/process_backups.c is missing."


def test_json_output_exists():
    """Test that the JSON output file was generated."""
    assert os.path.isfile(JSON_PATH), "The output file /home/user/valid_backups.json is missing."


def test_json_output_content():
    """Test that the JSON output correctly filters and maps the valid backups."""
    try:
        with open(JSON_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {JSON_PATH} does not contain valid JSON."

    assert isinstance(data, list), "The JSON output must be an array."

    expected_records = [
        {"id": 1, "ts": 1690000000, "db": "users_db", "bytes": 1048576},
        {"id": 3, "ts": 1690000100, "db": "graph_db", "bytes": 2048},
        {"id": 6, "ts": 1690000300, "db": "analytics_db", "bytes": 999999},
    ]

    assert len(data) == len(expected_records), (
        f"Expected {len(expected_records)} valid records in the JSON output, but found {len(data)}."
    )

    for i, (actual, expected) in enumerate(zip(data, expected_records)):
        assert "document" in actual, f"Record at index {i} is missing the 'document' key."
        doc = actual["document"]
        assert doc.get("id") == expected["id"], f"Record {i} 'id' mismatch. Expected {expected['id']}, got {doc.get('id')}."
        assert doc.get("ts") == expected["ts"], f"Record {i} 'ts' mismatch. Expected {expected['ts']}, got {doc.get('ts')}."
        assert doc.get("db") == expected["db"], f"Record {i} 'db' mismatch. Expected {expected['db']}, got {doc.get('db')}."
        assert doc.get("bytes") == expected["bytes"], f"Record {i} 'bytes' mismatch. Expected {expected['bytes']}, got {doc.get('bytes')}."

        assert "sql_param_query" in actual, f"Record at index {i} is missing the 'sql_param_query' key."
        assert actual["sql_param_query"] == EXPECTED_QUERY, f"Record {i} 'sql_param_query' mismatch."

        assert "sql_bind_args" in actual, f"Record at index {i} is missing the 'sql_bind_args' key."
        bind_args = actual["sql_bind_args"]
        assert isinstance(bind_args, list), f"Record {i} 'sql_bind_args' must be a list."
        assert len(bind_args) == 4, f"Record {i} 'sql_bind_args' must have exactly 4 elements."

        expected_bind_args = [str(expected["id"]), str(expected["ts"]), expected["db"], str(expected["bytes"])]
        assert bind_args == expected_bind_args, f"Record {i} 'sql_bind_args' mismatch. Expected {expected_bind_args}, got {bind_args}."


def test_program_processes_changed_csv_and_rejects_invalid_rows():
    original_csv = open(CSV_PATH, "rb").read()

    nonce = secrets.token_hex(6)
    id1 = 10000 + secrets.randbelow(80000)
    id2 = 100000 + secrets.randbelow(800000)
    id3 = 1000000 + secrets.randbelow(8000000)
    ts1 = 1700000000 + secrets.randbelow(1000000)
    ts2 = 1800000000 + secrets.randbelow(1000000)
    ts3 = 1900000000 + secrets.randbelow(1000000)
    size1 = 1 + secrets.randbelow(10000000)
    size2 = 1 + secrets.randbelow(10000000)
    size3 = 1 + secrets.randbelow(10000000)
    db1 = "db_" + nonce
    db2 = "A" * 50
    db3 = "archive_" + nonce

    rows = [
        "id,timestamp,db_name,status,size_bytes",
        f"{id1},{ts1},{db1},SUCCESS,{size1}",
        f"0,{ts1},zero_id,SUCCESS,10",
        f"-8,{ts1},negative_id,SUCCESS,10",
        f"77,0,zero_timestamp,SUCCESS,10",
        f"78,bad_timestamp,bad_ts,SUCCESS,10",
        f"79,{ts1},bad-name,SUCCESS,10",
        f"80,{ts1},{'B' * 51},SUCCESS,10",
        f"81,{ts1},failed_backup,FAILED,900",
        f"82,{ts1},zero_size,SUCCESS,0",
        f"83,{ts1},negative_size,SUCCESS,-20",
        f"84,{ts1},bad_size,SUCCESS,not_an_integer",
        f"85,{ts1},wrong_status,success,20",
        f"{id2},{ts2},{db2},SUCCESS,{size2}",
        f"86,{ts1},,SUCCESS,20",
        f"{id3},{ts3},{db3},SUCCESS,{size3}",
    ]

    expected = [
        {
            "document": {"id": id1, "ts": ts1, "db": db1, "bytes": size1},
            "sql_param_query": EXPECTED_QUERY,
            "sql_bind_args": [str(id1), str(ts1), db1, str(size1)],
        },
        {
            "document": {"id": id2, "ts": ts2, "db": db2, "bytes": size2},
            "sql_param_query": EXPECTED_QUERY,
            "sql_bind_args": [str(id2), str(ts2), db2, str(size2)],
        },
        {
            "document": {"id": id3, "ts": ts3, "db": db3, "bytes": size3},
            "sql_param_query": EXPECTED_QUERY,
            "sql_bind_args": [str(id3), str(ts3), db3, str(size3)],
        },
    ]

    try:
        with open(CSV_PATH, "w", newline="") as f:
            f.write("\n".join(rows) + "\n")
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)

        result = subprocess.run(
            [BINARY],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, "Program failed on a changed CSV:\n" + result.stderr
        assert os.path.isfile(JSON_PATH), "Program did not generate valid_backups.json for the changed CSV."

        try:
            with open(JSON_PATH, "r") as f:
                actual = json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"Program emitted invalid JSON for the changed CSV: {exc}"

        assert actual == expected, (
            "Program did not parse, validate, filter, and map the changed CSV correctly.\n"
            f"Expected: {expected!r}\nActual: {actual!r}"
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        subprocess.run([BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
