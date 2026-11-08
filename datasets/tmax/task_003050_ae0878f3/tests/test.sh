#!/bin/bash
set -u
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp -a /home/user/telemetry.jsonl "$backup_dir/telemetry.jsonl"
if [ -e /home/user/telemetry.db ]; then
    cp -a /home/user/telemetry.db "$backup_dir/telemetry.db"
    had_db=1
else
    had_db=0
fi

restore_files() {
    cp -a "$backup_dir/telemetry.jsonl" /home/user/telemetry.jsonl
    if [ "$had_db" -eq 1 ]; then
        cp -a "$backup_dir/telemetry.db" /home/user/telemetry.db
    else
        rm -f /home/user/telemetry.db
    fi
    rm -rf "$backup_dir"
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import pytest

def test_telemetry_db_exists():
    """Test that the SQLite database file was created."""
    assert os.path.exists("/home/user/telemetry.db"), "The database file /home/user/telemetry.db was not created."

def test_telemetry_db_contents():
    """Test that the database contains the correctly processed es-MX records."""
    db_path = "/home/user/telemetry.db"
    jsonl_path = "/home/user/telemetry.jsonl"

    assert os.path.exists(db_path), f"{db_path} is missing."
    assert os.path.exists(jsonl_path), f"{jsonl_path} is missing."

    expected_records = []
    window = []

    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                continue

            if data.get("locale") == "es-MX":
                latency = float(data.get("latency_ms", 0))
                window.append(latency)
                if len(window) > 5:
                    window.pop(0)

                rolling_avg = sum(window) / len(window)
                expected_records.append({
                    "id": str(data.get("id")),
                    "timestamp": data.get("timestamp"),
                    "latency_ms": latency,
                    "rolling_avg_latency": rolling_avg
                })

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='es_mx_stats'")
    assert cursor.fetchone() is not None, "Table 'es_mx_stats' does not exist in the database."

    cursor.execute("SELECT id, timestamp, latency_ms, rolling_avg_latency FROM es_mx_stats ORDER BY id ASC")
    db_records = cursor.fetchall()
    conn.close()

    expected_records.sort(key=lambda x: str(x["id"]))
    assert len(db_records) == len(expected_records), f"Expected {len(expected_records)} valid es-MX records in DB, found {len(db_records)}."

    for db_rec, exp_rec in zip(db_records, expected_records):
        db_id, db_ts, db_lat, db_avg = db_rec
        assert str(db_id) == exp_rec["id"], f"Expected ID {exp_rec['id']}, got {db_id}."
        assert db_ts == exp_rec["timestamp"], f"Expected timestamp {exp_rec['timestamp']} for ID {db_id}, got {db_ts}."
        assert abs(float(db_lat) - exp_rec["latency_ms"]) < 1e-5, f"Expected latency {exp_rec['latency_ms']} for ID {db_id}, got {db_lat}."
        assert abs(float(db_avg) - exp_rec["rolling_avg_latency"]) < 1e-5, f"Expected rolling avg {exp_rec['rolling_avg_latency']} for ID {db_id}, got {db_avg}."
TEST_EOF

run_checks() (
    set -e

    # Preserve all original final-state assertions.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Require the requested Go source and module, and check implementation evidence
    # for line streaming and transaction-based insertion.
    test -f /home/user/processor/process.go
    test -f /home/user/processor/go.mod
    python3 - << 'PY'
import re

path = "/home/user/processor/process.go"
source = open(path, "r", encoding="utf-8").read()

assert re.search(r'\bpackage\s+main\b', source), "process.go is not a main package"
assert re.search(r'\bfunc\s+main\s*\(', source), "process.go has no main function"
assert re.search(r'bufio\s*\.\s*New(?:Scanner|Reader)\s*\(', source), "telemetry must be read line-by-line with bufio"
assert not re.search(r'(?:os|ioutil)\s*\.\s*ReadFile\s*\(|io\s*\.\s*ReadAll\s*\(', source), "whole-file reads are not streaming"
assert re.search(r'\.\s*Begin(?:Tx)?\s*\(', source), "SQLite inserts must use a transaction"
assert re.search(r'\.\s*Commit\s*\(', source), "the insertion transaction is not committed"
assert re.search(r'(?is)(?:Exec|Prepare|PrepareContext)\s*\([^)]*INSERT\s+INTO\s+es_mx_stats', source), "no insertion into es_mx_stats was found"
PY

    cd /home/user/processor
    go list -m >/dev/null
    timeout 120s go build -o /tmp/submitted_processor ./process.go
    test -x /tmp/submitted_processor

    # Replace the input with unpredictable verifier-generated data, then execute
    # the submitted Go binary rather than trusting the pre-created database.
    python3 - << 'PY'
import json
import random
import uuid
from datetime import datetime, timedelta, timezone

rng = random.SystemRandom()
base = datetime(2026, 1, 1, tzinfo=timezone.utc)
locales = ["es-MX", "en-US", "es-MX", "fr-FR", "es-MX", "es-MX", "es-MX", "es-MX", "es-MX", "es-MX"]
with open("/home/user/telemetry.jsonl", "w", encoding="utf-8") as f:
    for i, locale in enumerate(locales):
        if i == 4:
            f.write('{"id":"broken-one","locale":"es-MX","latency_ms":17,"error":"' + chr(92) + 'uZZZZ"}\n')
        latency = round(rng.uniform(-25.0, 450.0), 4)
        row = {
            "id": str(uuid.uuid4()),
            "timestamp": (base + timedelta(seconds=i)).isoformat().replace("+00:00", "Z"),
            "locale": locale,
            "latency_ms": latency,
        }
        f.write(json.dumps(row) + "\n")
        if i == 7:
            f.write('{"id":"broken-two","locale":"es-MX","bad":"' + chr(92) + 'u00"}\n')
PY

    rm -f /home/user/telemetry.db /home/user/telemetry.db-wal /home/user/telemetry.db-shm
    cd /home/user/processor
    timeout 30s /tmp/submitted_processor >/tmp/submitted_processor.out 2>&1

    # Independently derive answers from the generated JSONL and verify the new DB.
    python3 - << 'PY'
import json
import os
import sqlite3

jsonl_path = "/home/user/telemetry.jsonl"
db_path = "/home/user/telemetry.db"
assert os.path.isfile(db_path), "executing the Go program did not create telemetry.db"

expected = []
window = []
with open(jsonl_path, "r", encoding="utf-8") as f:
    for line in f:
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if item.get("locale") != "es-MX":
            continue
        latency = float(item.get("latency_ms", 0))
        window.append(latency)
        window = window[-5:]
        expected.append((str(item.get("id")), item.get("timestamp"), latency, sum(window) / len(window)))

expected.sort(key=lambda row: row[0])
conn = sqlite3.connect(db_path)
try:
    table = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='es_mx_stats'").fetchone()
    assert table is not None, "Go program did not create es_mx_stats"
    actual = conn.execute("SELECT id, timestamp, latency_ms, rolling_avg_latency FROM es_mx_stats ORDER BY id ASC").fetchall()
finally:
    conn.close()

assert len(actual) == len(expected), (len(actual), len(expected))
for got, want in zip(actual, expected):
    assert str(got[0]) == want[0]
    assert got[1] == want[1]
    assert abs(float(got[2]) - want[2]) < 1e-5
    assert abs(float(got[3]) - want[3]) < 1e-5
PY
)

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
