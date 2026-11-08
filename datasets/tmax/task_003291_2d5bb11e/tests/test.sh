#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import hashlib
import json
import os
import sqlite3
from datetime import timezone

import dateparser
import pytest
from dateutil import parser as dateutil_parser

DB_PATH = "/home/user/config_history.db"
RAW_PATH = "/home/user/raw_configs.jsonl"


def get_hash(state_dict):
    compact_json = json.dumps(state_dict, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(compact_json.encode("utf-8")).hexdigest()


def parse_epoch(value):
    try:
        parsed = dateutil_parser.parse(value)
    except (TypeError, ValueError, OverflowError):
        parsed = dateparser.parse(
            value,
            settings={
                "TIMEZONE": "UTC",
                "TO_TIMEZONE": "UTC",
                "RETURN_AS_TIMEZONE_AWARE": True,
            },
        )

    assert parsed is not None, f"Could not parse timestamp from input: {value!r}"
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def derive_expected_records():
    expected = []
    seen = set()

    with open(RAW_PATH, "r", encoding="utf-8") as raw_file:
        for source_index, line in enumerate(raw_file):
            if not line.strip():
                continue

            record = json.loads(line)
            host_id = record["host_id"]
            state = copy.deepcopy(record["state"])

            for key in ("api_key", "password"):
                if key in state:
                    state[key] = "***"

            state_hash = get_hash(state)
            dedup_key = (host_id, state_hash)
            if dedup_key in seen:
                continue
            seen.add(dedup_key)

            expected.append(
                {
                    "source_index": source_index,
                    "host_id": host_id,
                    "epoch": parse_epoch(record["recorded_at"]),
                    "state_hash": state_hash,
                    "masked_state": state,
                }
            )

    return sorted(expected, key=lambda row: (row["epoch"], row["source_index"]))


def test_database_exists():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    assert os.path.isfile(DB_PATH), f"Path {DB_PATH} is not a file."


def test_table_schema():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='changes'")
    assert cur.fetchone() is not None, "Table 'changes' does not exist in the database."

    cur.execute("PRAGMA table_info(changes)")
    columns = {row[1]: row[2].upper() for row in cur.fetchall()}

    expected_columns = {
        "host_id": "TEXT",
        "epoch": "INTEGER",
        "state_hash": "TEXT",
        "masked_state": "TEXT",
    }

    for col, col_type in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from the 'changes' table."
        assert col_type in columns[col], (
            f"Column '{col}' has incorrect type. Expected {col_type}, got {columns[col]}"
        )

    conn.close()


def test_database_records():
    expected_data = derive_expected_records()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT * FROM changes ORDER BY epoch ASC, rowid ASC")
    rows = cur.fetchall()

    assert len(rows) == len(expected_data), (
        f"Expected exactly {len(expected_data)} records derived from {RAW_PATH}, "
        f"found {len(rows)}."
    )

    for i, expected in enumerate(expected_data):
        row = rows[i]
        assert row["host_id"] == expected["host_id"], (
            f"Record {i + 1}: Incorrect host_id. Expected {expected['host_id']}, "
            f"got {row['host_id']}"
        )
        assert row["epoch"] == expected["epoch"], (
            f"Record {i + 1}: Incorrect epoch timestamp. Expected {expected['epoch']}, "
            f"got {row['epoch']}"
        )

        try:
            actual_masked_state = json.loads(row["masked_state"])
        except (json.JSONDecodeError, TypeError):
            pytest.fail(f"Record {i + 1}: masked_state is not valid JSON.")

        assert actual_masked_state == expected["masked_state"], (
            f"Record {i + 1}: Incorrect masked_state. "
            f"Expected {expected['masked_state']}, got {actual_masked_state}"
        )
        assert row["state_hash"] == expected["state_hash"], (
            f"Record {i + 1}: Incorrect state_hash. "
            f"Expected {expected['state_hash']}, got {row['state_hash']}"
        )

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
