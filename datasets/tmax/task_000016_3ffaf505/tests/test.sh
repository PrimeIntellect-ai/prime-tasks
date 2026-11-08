#!/bin/bash
mkdir -p /logs/verifier

export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH

run_pipeline() {
    rm -f /home/user/data/measurements.db || return 1
    (cd /home/user/etl_pipeline && timeout 300s cargo run --quiet) || return 1
}

run_all_checks() {
    test -f /home/user/etl_pipeline/src/main.rs || return 1
    test ! -L /home/user/etl_pipeline/src/main.rs || return 1

    # Restore the original fixture, then require the submitted Rust project to
    # produce the database before running all of the original assertions.
    cat > /home/user/data/source_a.csv << 'EOF'
2023-10-01T10:00:00Z,s1,temp,22.5
2023-10-01T10:00:00Z,s1,temp,22.5
2023-10-01T10:01:00Z,s1,temp,-50.0
2023-10-01T10:02:00Z,s2,hum,45.0
2023-10-01T10:03:00Z,s3,pressure,1013.2
EOF

    cat > /home/user/data/source_b.csv << 'EOF'
2023-10-01T10:00:00Z,s1,hum,40.0
2023-10-01T10:02:00Z,s2,hum,45.0
2023-10-01T10:04:00Z,s2,temp,85.0
2023-10-01T10:05:00Z,s1,temp,23.0
EOF

    run_pipeline || return 1

    cat > /tmp/test_final_state.py << 'TEST_EOF'
import os
import sqlite3
import hashlib

DB_PATH = "/home/user/data/measurements.db"

def test_db_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created."

def test_table_schema():
    assert os.path.isfile(DB_PATH), "Database missing, cannot check schema."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='metrics';")
    assert cursor.fetchone() is not None, "Table 'metrics' does not exist in the database."
    cursor.execute("PRAGMA table_info(metrics);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
    expected_columns = {
        "hash": "TEXT",
        "timestamp": "TEXT",
        "sensor_id": "TEXT",
        "metric_type": "TEXT",
        "value": "REAL"
    }
    for col, col_type in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from the 'metrics' table."
        assert expected_columns[col] in columns[col], f"Column '{col}' should be of type {expected_columns[col]}, found {columns[col]}."
    conn.close()

def test_data_content():
    assert os.path.isfile(DB_PATH), "Database missing, cannot check data."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT hash, timestamp, sensor_id, metric_type, value FROM metrics;")
    rows = cursor.fetchall()
    conn.close()
    assert len(rows) == 4, f"Expected exactly 4 rows in the 'metrics' table, found {len(rows)}."
    expected_data = [
        ("2023-10-01T10:00:00Z", "s1", "temp", 22.5),
        ("2023-10-01T10:02:00Z", "s2", "hum", 45.0),
        ("2023-10-01T10:00:00Z", "s1", "hum", 40.0),
        ("2023-10-01T10:05:00Z", "s1", "temp", 23.0)
    ]
    expected_records = {}
    for ts, sid, mtype, val in expected_data:
        concat_str = f"{ts}{sid}{mtype}"
        h = hashlib.md5(concat_str.encode('utf-8')).hexdigest()
        expected_records[h] = (ts, sid, mtype, val)
    actual_records = {row[0]: (row[1], row[2], row[3], row[4]) for row in rows}
    for expected_hash, expected_tuple in expected_records.items():
        assert expected_hash in actual_records, f"Missing expected row with hash {expected_hash} (data: {expected_tuple}). Deduplication or hashing logic might be incorrect."
        actual_tuple = actual_records[expected_hash]
        assert actual_tuple == expected_tuple, f"Data mismatch for hash {expected_hash}. Expected {expected_tuple}, found {actual_tuple}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Generate an unpredictable second fixture that exercises both inputs,
    # boundary validation, invalid metrics, and first-seen deduplication.
    python3 - << 'PY_EOF' || return 1
import csv
import secrets

p = secrets.token_hex(16)
a = [
    (f"{p}-t0", f"{p}-s0", "temp", 17.25),
    (f"{p}-t0", f"{p}-s0", "temp", 19.75),
    (f"{p}-t1", f"{p}-s1", "temp", -40.0),
    (f"{p}-t2", f"{p}-s2", "hum", 100.0),
    (f"{p}-t3", f"{p}-s3", "hum", -0.25),
    (f"{p}-t4", f"{p}-s4", "pressure", 10.0),
]
b = [
    (f"{p}-t0", f"{p}-s0", "temp", 77.0),
    (f"{p}-t5", f"{p}-s5", "hum", 0.0),
    (f"{p}-t6", f"{p}-s6", "temp", 80.0),
    (f"{p}-t7", f"{p}-s7", "temp", 80.25),
    (f"{p}-t8", f"{p}-s8", "hum", 100.25),
]
for path, rows in [("/home/user/data/source_a.csv", a), ("/home/user/data/source_b.csv", b)]:
    with open(path, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
PY_EOF

    local a_hash b_hash
    a_hash=$(sha256sum /home/user/data/source_a.csv | awk '{print $1}') || return 1
    b_hash=$(sha256sum /home/user/data/source_b.csv | awk '{print $1}') || return 1

    run_pipeline || return 1

    test "$a_hash" = "$(sha256sum /home/user/data/source_a.csv | awk '{print $1}')" || return 1
    test "$b_hash" = "$(sha256sum /home/user/data/source_b.csv | awk '{print $1}')" || return 1

    cat > /tmp/test_dynamic_state.py << 'TEST_EOF'
import csv
import hashlib
import os
import sqlite3

DB_PATH = "/home/user/data/measurements.db"
SOURCE_PATHS = ["/home/user/data/source_a.csv", "/home/user/data/source_b.csv"]

def expected_records():
    expected = {}
    for path in SOURCE_PATHS:
        with open(path, newline="") as f:
            for row in csv.reader(f):
                assert len(row) == 4
                ts, sid, metric, raw_value = row
                value = float(raw_value)
                valid = ((metric == "temp" and -40.0 <= value <= 80.0) or
                         (metric == "hum" and 0.0 <= value <= 100.0))
                if not valid:
                    continue
                digest = hashlib.md5((ts + sid + metric).encode("utf-8")).hexdigest()
                if digest not in expected:
                    expected[digest] = (ts, sid, metric, value)
    return expected

def test_dynamic_etl_result():
    assert os.path.isfile(DB_PATH), "The dynamic run did not create measurements.db"
    expected = expected_records()
    conn = sqlite3.connect(DB_PATH)
    try:
        table = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='metrics'").fetchone()
        assert table is not None, "Table 'metrics' is missing after the dynamic run"
        rows = conn.execute("SELECT hash, timestamp, sensor_id, metric_type, value FROM metrics").fetchall()
    finally:
        conn.close()
    actual = {row[0]: (row[1], row[2], row[3], row[4]) for row in rows}
    assert len(rows) == len(expected), f"Expected {len(expected)} dynamic rows, found {len(rows)}"
    assert actual == expected, f"Dynamic ETL output mismatch. Expected {expected}, found {actual}"
TEST_EOF

    python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short || return 1
}

if run_all_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
