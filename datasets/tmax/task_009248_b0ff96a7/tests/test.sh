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
import tempfile
import pytest

EXPORT_TOOL = "/home/user/export_tool.py"
RESULTS = "/home/user/export_results.json"


def test_01_artifacts_are_regular_files():
    for path in (EXPORT_TOOL, "/home/user/run_export.sh"):
        assert os.path.exists(path), f"Required artifact {path} does not exist."
        assert not os.path.islink(path), f"Required artifact {path} must not be a symbolic link."
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required artifact {path} must be a regular file."
    assert os.access("/home/user/run_export.sh", os.X_OK), "run_export.sh must be executable."


def test_02_ticket_resolution_file():
    filepath = "/home/user/ticket_resolution.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r", encoding="utf-8") as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]

    # Preserve the original assertions.
    assert len(lines) >= 2, f"{filepath} must contain at least two lines."
    line1 = lines[0]
    line2 = lines[1]
    assert "Corrupted input:" in line1, "Line 1 must contain 'Corrupted input:'"
    assert "ERR_CORRUPT_882A" in line1, f"Line 1 should contain the exact corrupted string. Found: {line1}"
    assert "Circular alias IDs:" in line2, "Line 2 must contain 'Circular alias IDs:'"
    assert "10" in line2 and "11" in line2, f"Line 2 should contain the IDs involved in the cycle (10 and 11). Found: {line2}"

    # The requested file has exactly two complete, non-empty lines and exact labels/values.
    assert len(raw_lines) == 2, f"{filepath} must contain exactly two lines."
    assert raw_lines[0] == "Corrupted input: ERR_CORRUPT_882A"
    assert raw_lines[1] in {"Circular alias IDs: 10,11", "Circular alias IDs: 11,10"}


def test_03_export_results_json():
    filepath = RESULTS
    assert os.path.isfile(filepath), f"File {filepath} does not exist. Did the script run successfully?"

    with open(filepath, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{filepath} is not a valid JSON file.")

    assert isinstance(data, list), "JSON output should be a list of records."

    # Preserve the original assertions.
    expected_ids = {1, 2, 10, 3}
    actual_ids = {record.get("id") for record in data}
    assert expected_ids.issubset(actual_ids), f"Expected records for IDs {expected_ids}, but found {actual_ids}."
    assert len(data) == 4, f"Expected exactly 4 records in the JSON output, but found {len(data)}."
    record_10 = next((r for r in data if r.get("id") == 10), None)
    assert record_10 is not None, "Record for ID 10 is missing."
    assert record_10.get("real_id") == 10, f"For ID 10, real_id should be 10 due to cycle detection. Found: {record_10.get('real_id')}"

    expected = [
        {"id": 1, "real_id": 1, "name": "Alice", "email": "alice@example.com"},
        {"id": 2, "real_id": 2, "name": "Bob", "email": "bob@example.com"},
        {"id": 10, "real_id": 10, "name": "Dave", "email": "dave@example.com"},
        {"id": 3, "real_id": 3, "name": "Charlie", "email": "charlie@example.com"},
    ]
    assert data == expected, "The wrapper-generated report does not contain the exact expected records."


def test_04_general_input_and_alias_behavior():
    original_results = open(RESULTS, "rb").read()
    base = 100000 + secrets.randbelow(800000)
    plain, terminal, alias = base, base + 1, base + 2
    cycle_a, cycle_b, cycle_c = base + 3, base + 4, base + 5
    unknown = base + 99
    token = secrets.token_hex(8)

    rows = [
        (plain, f"Plain-{token}", f"plain-{token}@example.test", None),
        (terminal, f"Terminal-{token}", f"terminal-{token}@example.test", None),
        (alias, f"Alias-{token}", f"alias-{token}@example.test", terminal),
        (cycle_a, f"CycleA-{token}", f"cycle-a-{token}@example.test", cycle_b),
        (cycle_b, f"CycleB-{token}", f"cycle-b-{token}@example.test", cycle_c),
        (cycle_c, f"CycleC-{token}", f"cycle-c-{token}@example.test", cycle_b),
    ]

    try:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = os.path.join(tmp, "dynamic.db")
            input_path = os.path.join(tmp, "dynamic_ids.txt")
            conn = sqlite3.connect(db_path)
            conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, alias_id INTEGER)")
            conn.executemany("INSERT INTO users (id, name, email, alias_id) VALUES (?, ?, ?, ?)", rows)
            conn.commit()
            conn.close()

            with open(input_path, "w", encoding="utf-8") as f:
                f.write(f"{plain}\nBAD_{token}\n{alias}\n{cycle_a}\n{cycle_b}\n12x{token}\n{cycle_c}\n{unknown}\n")

            if os.path.exists(RESULTS):
                os.remove(RESULTS)
            proc = subprocess.run(
                ["python3", EXPORT_TOOL, input_path, db_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=8,
            )
            assert proc.returncode == 0, f"export_tool.py failed on a valid fixture: {proc.stderr}"
            assert os.path.isfile(RESULTS), "export_tool.py did not generate export_results.json."
            with open(RESULTS, "r", encoding="utf-8") as f:
                actual = json.load(f)
    finally:
        with open(RESULTS, "wb") as f:
            f.write(original_results)

    expected = [
        {"id": plain, "real_id": plain, "name": rows[0][1], "email": rows[0][2]},
        {"id": alias, "real_id": terminal, "name": rows[1][1], "email": rows[1][2]},
        {"id": cycle_a, "real_id": cycle_a, "name": rows[3][1], "email": rows[3][2]},
        {"id": cycle_b, "real_id": cycle_b, "name": rows[4][1], "email": rows[4][2]},
        {"id": cycle_c, "real_id": cycle_c, "name": rows[5][1], "email": rows[5][2]},
    ]
    assert actual == expected, "Malformed lines, aliases, or general cycle detection were handled incorrectly."
TEST_EOF

rm -f /home/user/export_results.json
if timeout 10s /home/user/run_export.sh >/tmp/run_export.stdout 2>/tmp/run_export.stderr && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
