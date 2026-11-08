#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import json
import os
import re
import secrets
import sqlite3
import subprocess

import jsonschema

DB_PATH = "/home/user/backups.db"
REPORT_PATH = "/home/user/lineage_report.json"
SCRIPT_PATH = "/home/user/analyze_backups.py"

SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "id": {"type": "string"},
            "parent_id": {"type": ["string", "null"]},
            "size_bytes": {"type": "integer"},
            "start_time": {"type": "string"},
            "cumulative_size_bytes": {"type": "integer"},
        },
        "required": ["id", "size_bytes", "start_time", "cumulative_size_bytes"],
    },
}


def create_database(rows):
    if os.path.lexists(DB_PATH):
        os.remove(DB_PATH)
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)

    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE jobs (id TEXT PRIMARY KEY, parent_id TEXT, "
        "size_bytes INTEGER, start_time DATETIME)"
    )
    conn.executemany("INSERT INTO jobs VALUES (?, ?, ?, ?)", rows)
    conn.commit()
    conn.close()


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_backups.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_index_exists_and_is_correct():
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    result = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_jobs_parent'"
    ).fetchone()
    assert result is not None, "Index 'idx_jobs_parent' does not exist in the database."
    assert result[0] == "idx_jobs_parent", "Index name mismatch."
    columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_jobs_parent')")]
    conn.close()
    assert columns == ["parent_id"], (
        "Index 'idx_jobs_parent' must index exactly the jobs.parent_id column."
    )


def load_and_validate_report():
    assert os.path.isfile(REPORT_PATH), f"JSON report missing: {REPORT_PATH}"
    try:
        with open(REPORT_PATH, "r", encoding="utf-8") as report_file:
            data = json.load(report_file)
    except json.JSONDecodeError as exc:
        raise AssertionError("lineage_report.json does not contain valid JSON") from exc
    jsonschema.validate(instance=data, schema=SCHEMA)
    assert isinstance(data, list), "The JSON output should be a list of dictionaries."
    return data


def expected_lineage(rows):
    by_id = {row[0]: row for row in rows}
    descendants = {"BKP-001"}
    changed = True
    while changed:
        changed = False
        for job_id, parent_id, _, _ in rows:
            if parent_id in descendants and job_id not in descendants:
                descendants.add(job_id)
                changed = True

    selected = [by_id[job_id] for job_id in descendants]
    selected.sort(key=lambda row: (row[3], row[0]))
    total = 0
    expected = {}
    for job_id, parent_id, size_bytes, start_time in selected:
        total += size_bytes
        expected[job_id] = {
            "id": job_id,
            "parent_id": parent_id,
            "size_bytes": size_bytes,
            "start_time": start_time,
            "cumulative_size_bytes": total,
        }
    return expected


def assert_report_matches(rows, data):
    expected = expected_lineage(rows)
    assert len(data) == len(expected), (
        f"Should contain exactly {len(expected)} jobs in the lineage, found {len(data)}."
    )
    found_ids = set()
    for row in data:
        assert isinstance(row, dict), "Each item in the JSON array must be an object/dictionary."
        for field in ("id", "parent_id", "size_bytes", "start_time", "cumulative_size_bytes"):
            assert field in row, f"Missing '{field}' in report row."
        job_id = row["id"]
        assert job_id not in found_ids, f"Duplicate job id {job_id} found in the report."
        found_ids.add(job_id)
        assert job_id in expected, f"Unexpected job id {job_id} found in the report."
        for field, value in expected[job_id].items():
            assert row[field] == value, (
                f"Incorrect {field} for {job_id}. Expected {value!r}, got {row[field]!r}."
            )
    assert found_ids == set(expected), "Not all expected jobs were found in the report."


def assert_required_implementation_is_present():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "analyze_backups.py must be a regular script, not a symlink."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as script_file:
        source = script_file.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        raise AssertionError("analyze_backups.py is not valid Python") from exc

    string_literals = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    recursive_window_queries = [
        value for value in string_literals
        if re.search(r"\bWITH\s+RECURSIVE\b", value, re.IGNORECASE | re.DOTALL)
        and re.search(r"\bSUM\s*\([^)]*size_bytes[^)]*\)\s*OVER\s*\(", value, re.IGNORECASE | re.DOTALL)
        and re.search(r"ORDER\s+BY\s+[^)]*start_time", value, re.IGNORECASE | re.DOTALL)
    ]
    assert recursive_window_queries, (
        "The script must contain a single SQL query using WITH RECURSIVE and a "
        "SUM(size_bytes) window ordered by start_time."
    )

    assert any(
        re.search(r"CREATE\s+INDEX(?:\s+IF\s+NOT\s+EXISTS)?\s+idx_jobs_parent\s+ON\s+jobs\s*\(\s*parent_id\s*\)",
                  value, re.IGNORECASE | re.DOTALL)
        for value in string_literals
    ), "The script must create idx_jobs_parent on jobs(parent_id)."

    validation_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == "validate":
                validation_calls.append(node)
            elif isinstance(node.func, ast.Attribute) and node.func.attr == "validate":
                validation_calls.append(node)
    assert validation_calls, "The script must call JSON Schema validation before writing the report."
    for required_text in ("jsonschema", "cumulative_size_bytes", "size_bytes", "start_time", "required"):
        assert required_text in source, f"The required JSON Schema is missing {required_text!r}."


def test_complete_backup_analysis():
    assert_required_implementation_is_present()

    canonical_rows = [
        ("BKP-001", None, 1000, "2023-10-01 10:00:00"),
        ("BKP-002", "BKP-001", 500, "2023-10-01 10:05:00"),
        ("BKP-003", "BKP-001", 750, "2023-10-01 10:10:00"),
        ("BKP-004", "BKP-002", 200, "2023-10-01 10:15:00"),
        ("BKP-005", "BKP-003", 100, "2023-10-01 10:20:00"),
        ("BKP-006", "BKP-009", 5000, "2023-10-01 10:25:00"),
    ]
    create_database(canonical_rows)
    run_script()
    assert_index_exists_and_is_correct()
    canonical_report = load_and_validate_report()
    assert_report_matches(canonical_rows, canonical_report)

    token = secrets.token_hex(5)
    base = datetime.datetime(2026, 1, 1, 8, 0, 0)
    ids = ["BKP-001"] + [f"JOB-{token}-{i}" for i in range(1, 8)]
    parents = [None, ids[0], ids[0], ids[1], ids[3], ids[2], ids[5], ids[1]]
    minute_offsets = [31, 4, 47, 13, 59, 22, 38, 52]
    challenge_rows = []
    for i, job_id in enumerate(ids):
        timestamp = (base + datetime.timedelta(minutes=minute_offsets[i])).strftime("%Y-%m-%d %H:%M:%S")
        challenge_rows.append((job_id, parents[i], secrets.randbelow(9000) + 101, timestamp))
    challenge_rows.extend([
        (f"OUTSIDE-{token}-1", None, 70001, "2025-12-01 00:00:00"),
        (f"OUTSIDE-{token}-2", f"OUTSIDE-{token}-1", 80003, "2025-12-01 00:01:00"),
    ])

    create_database(challenge_rows)
    run_script()
    assert_index_exists_and_is_correct()
    challenge_report = load_and_validate_report()
    assert_report_matches(challenge_rows, challenge_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
