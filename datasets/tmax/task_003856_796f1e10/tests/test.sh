#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import sqlite3

FINAL_METRIC_PATH = "/home/user/final_metric.txt"
WORKSPACE = "/home/user/build_workspace"
DB_PATH = os.path.join(WORKSPACE, "results.db")
DATA_DIR = os.path.join(WORKSPACE, "data")


def test_final_metric_exists():
    assert os.path.isfile(FINAL_METRIC_PATH), f"Expected output file {FINAL_METRIC_PATH} does not exist."


def test_final_metric_content():
    assert os.path.isfile(FINAL_METRIC_PATH), f"Output file {FINAL_METRIC_PATH} is missing."

    with open(FINAL_METRIC_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # The sum of 1 to 50 is 50 * 51 / 2 = 1275
    expected_sum = "1275"

    assert content == expected_sum, f"Expected final metric to be '{expected_sum}', but got '{content}'."


def test_metric_matches_recovered_database_and_utf16_input():
    assert os.path.isfile(DB_PATH), f"SQLite database {DB_PATH} is missing."

    # Opening the database normally in read-only mode makes SQLite apply any
    # committed records still present in its WAL.
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert conn.execute("PRAGMA journal_mode").fetchone()[0].lower() == "wal"
        columns = conn.execute("PRAGMA table_info(records)").fetchall()
        assert [column[1] for column in columns] == ["id", "value"]
        rows = conn.execute("SELECT id, value FROM records ORDER BY id").fetchall()
    finally:
        conn.close()

    expected_rows = [(i, i) for i in range(1, 51) if i != 42]
    assert rows == expected_rows, "The recovered SQLite records are incomplete or were altered."

    json_paths = sorted(glob.glob(os.path.join(DATA_DIR, "*.json")))
    assert json_paths == [os.path.join(DATA_DIR, "data_42.json")], \
        f"Expected the single remaining input data_42.json, found: {json_paths}"

    with open(json_paths[0], "rb") as f:
        raw = f.read()

    # Confirm this is the problematic UTF-16LE serialization rather than an
    # ordinary UTF-8 JSON file, then decode and parse it correctly.
    try:
        json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        pass
    else:
        raise AssertionError("data_42.json unexpectedly parses as UTF-8 JSON")

    remaining = json.loads(raw.decode("utf-16le"))
    assert remaining == {"id": 42, "value": 42}, \
        "The remaining UTF-16LE JSON record is invalid or was altered."

    recovered_total = sum(value for _, value in rows) + remaining["value"]
    with open(FINAL_METRIC_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == str(recovered_total), \
        f"Final metric does not match the recovered total {recovered_total}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
