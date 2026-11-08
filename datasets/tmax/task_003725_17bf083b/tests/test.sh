#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import stat
import subprocess
import pytest

DB_PATH = "/home/user/telemetry.db"
JSON_PATH = "/home/user/clean_backup.json"
SCRIPT_PATH = "/home/user/fix_and_extract.py"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def reset_corrupted_index(conn):
    conn.execute("DROP INDEX IF EXISTS idx_telemetry_optimal")
    conn.execute("DROP INDEX IF EXISTS idx_telemetry_node")
    conn.execute("CREATE INDEX idx_telemetry_node ON telemetry(node_id)")
    conn.commit()


def test_script_executes_pipeline_on_database_contents():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular Python script."

    conn = sqlite3.connect(DB_PATH)
    base = 1000000 + secrets.randbelow(100000000)
    while conn.execute(
        "SELECT 1 FROM nodes WHERE node_id IN (?, ?, ?)",
        (base, base + 1, base + 2),
    ).fetchone() is not None or conn.execute(
        "SELECT 1 FROM telemetry WHERE id IN (?, ?, ?)",
        (base, base + 1, base + 2),
    ).fetchone() is not None:
        base += 3

    token = secrets.token_hex(8)
    timestamp = f"2099-12-31T23:59:{secrets.randbelow(60):02d}Z-{token}"
    metric = float(1000 + secrets.randbelow(100000)) + 0.375

    conn.executemany(
        "INSERT INTO nodes(node_id, status, region) VALUES (?, ?, ?)",
        [
            (base, "ACTIVE", "us-east"),
            (base + 1, "INACTIVE", "us-east"),
            (base + 2, "ACTIVE", "us-west"),
        ],
    )
    conn.executemany(
        "INSERT INTO telemetry(id, node_id, ts, metric) VALUES (?, ?, ?, ?)",
        [
            (base, base, timestamp, metric),
            (base + 1, base + 1, timestamp, metric + 1.0),
            (base + 2, base + 2, timestamp, metric + 2.0),
        ],
    )
    reset_corrupted_index(conn)

    rows = conn.execute(
        """
        SELECT t.id, t.node_id, t.ts, t.metric
        FROM telemetry AS t
        JOIN nodes AS n ON n.node_id = t.node_id
        WHERE n.status = 'ACTIVE' AND n.region = 'us-east'
        """
    ).fetchall()
    expected = [
        {
            "telemetry_id": row[0],
            "node_id": row[1],
            "timestamp": row[2],
            "metric_value": float(row[3]),
        }
        for row in rows
    ]
    conn.close()

    if os.path.lexists(JSON_PATH):
        os.unlink(JSON_PATH)
    run_script()

    with open(JSON_PATH, "r") as f:
        content = f.read()
    data = json.loads(content)
    assert isinstance(data, list), "The exported JSON must be an array."
    assert "\n  {" in content or "\n  \"" in content, \
        "The JSON output must be formatted with an indent of 2 spaces."

    required_keys = {"telemetry_id", "node_id", "timestamp", "metric_value"}
    for record in data:
        assert set(record) == required_keys, f"Record has the wrong schema: {record}"
        assert type(record["telemetry_id"]) is int, "telemetry_id must be an integer."
        assert type(record["node_id"]) is int, "node_id must be an integer."
        assert type(record["timestamp"]) is str, "timestamp must be a string."
        assert type(record["metric_value"]) is float, "metric_value must be a float."

    assert sorted(data, key=lambda x: x["telemetry_id"]) == sorted(
        expected, key=lambda x: x["telemetry_id"]
    ), "The script did not derive the export from the required join and filters."

    conn = sqlite3.connect(DB_PATH)
    assert conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_telemetry_node'"
    ).fetchone() is None, "The executed script did not drop idx_telemetry_node."
    assert conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_telemetry_optimal'"
    ).fetchone() is not None, "The executed script did not create idx_telemetry_optimal."

    conn.execute("DELETE FROM telemetry WHERE id IN (?, ?, ?)", (base, base + 1, base + 2))
    conn.execute("DELETE FROM nodes WHERE node_id IN (?, ?, ?)", (base, base + 1, base + 2))
    reset_corrupted_index(conn)
    conn.close()

    os.unlink(JSON_PATH)
    run_script()


def test_database_indices():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check that old index is dropped
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_telemetry_node';")
    assert cursor.fetchone() is None, "The corrupted index 'idx_telemetry_node' was not dropped."

    # Check that new index exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_telemetry_optimal';")
    assert cursor.fetchone() is not None, "The new index 'idx_telemetry_optimal' was not created."

    # Check the columns of the new index
    cursor.execute("PRAGMA index_info('idx_telemetry_optimal');")
    columns = [row[2] for row in cursor.fetchall()]
    expected_columns = ['node_id', 'ts', 'metric']
    assert columns == expected_columns, f"Expected index columns {expected_columns}, but got {columns}."

    conn.close()


def test_json_export():
    assert os.path.isfile(JSON_PATH), f"Exported JSON file {JSON_PATH} is missing."

    with open(JSON_PATH, 'r') as f:
        content = f.read()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The exported JSON must be an array."

    expected_data = [
        {
            "telemetry_id": 101,
            "node_id": 1,
            "timestamp": "2023-10-01T10:00:00Z",
            "metric_value": 99.5
        },
        {
            "telemetry_id": 102,
            "node_id": 1,
            "timestamp": "2023-10-01T10:05:00Z",
            "metric_value": 98.2
        },
        {
            "telemetry_id": 105,
            "node_id": 4,
            "timestamp": "2023-10-01T10:15:00Z",
            "metric_value": 91.1
        }
    ]

    data_sorted = sorted(data, key=lambda x: x.get('telemetry_id', 0))
    expected_sorted = sorted(expected_data, key=lambda x: x['telemetry_id'])

    assert len(data_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} records, found {len(data_sorted)}."

    for i, record in enumerate(data_sorted):
        expected = expected_sorted[i]
        assert isinstance(record.get('telemetry_id'), int), "telemetry_id must be an integer."
        assert isinstance(record.get('node_id'), int), "node_id must be an integer."
        assert isinstance(record.get('timestamp'), str), "timestamp must be a string."
        assert isinstance(record.get('metric_value'), float), "metric_value must be a float."
        assert record == expected, f"Record mismatch. Expected {expected}, got {record}."

    assert "\n  {" in content or "\n  \"" in content, "The JSON output must be formatted with an indent of 2 spaces."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
