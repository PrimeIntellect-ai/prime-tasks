#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import secrets
import sqlite3
import subprocess
import uuid
from pathlib import Path

import pytest

DB_PATH = "/home/user/configs.db"
CSV_PATH = "/home/user/final_averages.csv"
RAW_PATH = "/home/user/raw_configs.jsonl"


def remove_outputs():
    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", CSV_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def write_corrupt_jsonl(records):
    with open(RAW_PATH, "w", encoding="utf-8") as f:
        for record in records:
            line = json.dumps(record).replace("\\\\u", "\\u")
            f.write(line + "\n")


def canonical_records():
    return [
        {"timestamp": 100, "server_id": "srv-A", "temp_celsius": 40.0, "cpu_load": 10.0, "metadata": "ok"},
        {"timestamp": 110, "server_id": "srv-A", "temp_celsius": None, "cpu_load": None, "metadata": "bad \\uZZZZ"},
        {"timestamp": 120, "server_id": "srv-A", "temp_celsius": 50.0, "cpu_load": 20.0, "metadata": "ok"},
        {"timestamp": 120, "server_id": "srv-A", "temp_celsius": 99.0, "cpu_load": 99.0, "metadata": "dup"},
        {"timestamp": 100, "server_id": "srv-B", "temp_celsius": None, "cpu_load": None, "metadata": "\\uG123"},
        {"timestamp": 110, "server_id": "srv-B", "temp_celsius": 60.0, "cpu_load": 30.0, "metadata": "ok"},
        {"timestamp": 120, "server_id": "srv-B", "temp_celsius": 70.0, "cpu_load": 40.0, "metadata": "ok"},
        {"timestamp": 130, "server_id": "srv-B", "temp_celsius": None, "cpu_load": None, "metadata": "ok"},
    ]


def find_pipeline_scripts():
    candidates = []
    all_sources = []
    for path in Path("/home/user").rglob("*.py"):
        if any(part.startswith(".") for part in path.relative_to("/home/user").parts):
            continue
        try:
            source = path.read_text(encoding="utf-8")
            ast.parse(source)
        except (OSError, UnicodeDecodeError, SyntaxError):
            continue
        all_sources.append((path, source))
        if all(name in source for name in ("raw_configs.jsonl", "configs.db", "final_averages.csv")):
            candidates.append((path, source))

    assert candidates, "No self-contained Python ETL script was found under /home/user."

    # Prefer an explicit executable entry point, but permit a top-level script.
    candidates.sort(key=lambda item: ("__main__" not in item[1], len(str(item[0]))))
    return candidates, all_sources


def assert_required_implementation(all_sources):
    sha_found = False
    parallel_found = False

    for _, source in all_sources:
        tree = ast.parse(source)
        module_aliases = set()
        parallel_call_names = set()
        hashlib_aliases = set()
        sha_call_names = set()

        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == "multiprocessing":
                        module_aliases.add(alias.asname or alias.name)
                    if alias.name == "concurrent.futures":
                        module_aliases.add(alias.asname or alias.name)
                    if alias.name == "hashlib":
                        hashlib_aliases.add(alias.asname or alias.name)
            elif isinstance(node, ast.ImportFrom):
                if node.module in ("multiprocessing", "concurrent.futures"):
                    for alias in node.names:
                        if alias.name in ("Pool", "Process", "ProcessPoolExecutor"):
                            parallel_call_names.add(alias.asname or alias.name)
                if node.module == "hashlib":
                    for alias in node.names:
                        if alias.name in ("sha256", "new"):
                            sha_call_names.add(alias.asname or alias.name)

        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            if isinstance(func, ast.Name):
                if func.id in parallel_call_names:
                    parallel_found = True
                if func.id in sha_call_names:
                    if func.id != "new" or (node.args and isinstance(node.args[0], ast.Constant) and str(node.args[0].value).lower() == "sha256"):
                        sha_found = True
            elif isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
                if func.value.id in module_aliases and func.attr in ("Pool", "Process", "ProcessPoolExecutor"):
                    parallel_found = True
                if func.value.id in hashlib_aliases and func.attr == "sha256":
                    sha_found = True
                if func.value.id in hashlib_aliases and func.attr == "new" and node.args and isinstance(node.args[0], ast.Constant) and str(node.args[0].value).lower() == "sha256":
                    sha_found = True

    assert sha_found, "The ETL implementation does not compute a SHA-256 hash."
    assert parallel_found, "The ETL implementation does not invoke a multiprocessing process API."


def run_script(path):
    result = subprocess.run(
        ["python3", str(path)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, f"ETL script {path} failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(DB_PATH), "Running the ETL script did not create configs.db."
    assert os.path.isfile(CSV_PATH), "Running the ETL script did not create final_averages.csv."


def check_generated_results(expected_rows, expected_averages):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT server_id, timestamp, temp_celsius, cpu_load FROM metrics ORDER BY server_id, timestamp"
        ).fetchall()
    finally:
        conn.close()

    assert len(rows) == len(expected_rows)
    for actual, expected in zip(rows, expected_rows):
        assert actual[0] == expected[0]
        assert actual[1] == expected[1]
        assert actual[2] == pytest.approx(expected[2])
        assert actual[3] == pytest.approx(expected[3])

    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        csv_rows = list(reader)
    assert reader.fieldnames == ["server_id", "avg_temp", "avg_load"]
    assert len(csv_rows) == len(expected_averages)
    by_server = {row["server_id"]: row for row in csv_rows}
    assert set(by_server) == set(expected_averages)
    for server_id, (avg_temp, avg_load) in expected_averages.items():
        assert float(by_server[server_id]["avg_temp"]) == pytest.approx(round(avg_temp, 2))
        assert float(by_server[server_id]["avg_load"]) == pytest.approx(round(avg_load, 2))


def test_00_pipeline_exists_and_runs_on_unseen_input():
    candidates, all_sources = find_pipeline_scripts()
    assert_required_implementation(all_sources)

    suffix = uuid.uuid4().hex[:10]
    server_x = "dynamic-X-" + suffix
    server_y = "dynamic-Y-" + suffix
    base = secrets.randbelow(200) + 20

    x_temps = (float(base), float(base + 8), float(base + 16))
    x_loads = (float(base + 3), float(base + 9), float(base + 15))
    y_temp = float(base + 31)
    y_load = float(base + 7)

    records = [
        {"timestamp": 410, "server_id": server_x, "temp_celsius": x_temps[0], "cpu_load": x_loads[0], "metadata": "ok"},
        {"timestamp": 420, "server_id": server_x, "temp_celsius": None, "cpu_load": None, "metadata": "broken \\uQ9Q9"},
        {"timestamp": 430, "server_id": server_x, "temp_celsius": x_temps[2], "cpu_load": x_loads[2], "metadata": "ok"},
        {"timestamp": 430, "server_id": server_x, "temp_celsius": 9999.0, "cpu_load": 9999.0, "metadata": "later duplicate"},
        {"timestamp": 700, "server_id": server_y, "temp_celsius": None, "cpu_load": None, "metadata": "\\uNOPE"},
        {"timestamp": 710, "server_id": server_y, "temp_celsius": y_temp, "cpu_load": y_load, "metadata": "ok"},
        {"timestamp": 720, "server_id": server_y, "temp_celsius": None, "cpu_load": None, "metadata": "ok"},
    ]
    expected_rows = sorted([
        (server_x, 410, x_temps[0], x_loads[0]),
        (server_x, 420, x_temps[1], x_loads[1]),
        (server_x, 430, x_temps[2], x_loads[2]),
        (server_y, 700, y_temp, y_load),
        (server_y, 710, y_temp, y_load),
        (server_y, 720, y_temp, y_load),
    ])
    expected_averages = {
        server_x: (sum(x_temps) / 3, sum(x_loads) / 3),
        server_y: (y_temp, y_load),
    }

    selected = None
    errors = []
    try:
        for path, _ in candidates:
            write_corrupt_jsonl(records)
            remove_outputs()
            try:
                run_script(path)
                check_generated_results(expected_rows, expected_averages)
                selected = path
                break
            except Exception as exc:
                errors.append(f"{path}: {exc}")
        assert selected is not None, "No ETL script correctly processed unseen input:\n" + "\n".join(errors)
    finally:
        # Restore the supplied fixture and regenerate final artifacts so the
        # original verifier assertions below are still exercised.
        write_corrupt_jsonl(canonical_records())
        remove_outputs()
        if selected is not None:
            run_script(selected)


def test_database_exists_and_schema():
    """Test that the SQLite database exists and has the correct schema."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='metrics'")
    table = cursor.fetchone()
    assert table is not None, "Table 'metrics' does not exist in the database."

    cursor.execute("PRAGMA table_info(metrics)")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    expected_columns = {
        'server_id': 'TEXT',
        'timestamp': 'INTEGER',
        'temp_celsius': 'REAL',
        'cpu_load': 'REAL'
    }
    for col, col_type in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from 'metrics' table."
        assert expected_columns[col] in columns[col].upper() or columns[col] == '', f"Column '{col}' has unexpected type {columns[col]}."
    conn.close()


def test_database_records():
    """Test that the database contains the correct interpolated and deduplicated records."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM metrics ORDER BY server_id, timestamp")
    rows = cursor.fetchall()
    assert len(rows) == 7, f"Expected 7 records in the database, found {len(rows)}."
    records = [dict(row) for row in rows]

    srv_a = [r for r in records if r['server_id'] == 'srv-A']
    assert len(srv_a) == 3, "Expected 3 records for srv-A."
    assert srv_a[0]['timestamp'] == 100 and srv_a[0]['temp_celsius'] == 40.0 and srv_a[0]['cpu_load'] == 10.0
    assert srv_a[1]['timestamp'] == 110 and srv_a[1]['temp_celsius'] == 45.0 and srv_a[1]['cpu_load'] == 15.0
    assert srv_a[2]['timestamp'] == 120 and srv_a[2]['temp_celsius'] == 50.0 and srv_a[2]['cpu_load'] == 20.0

    srv_b = [r for r in records if r['server_id'] == 'srv-B']
    assert len(srv_b) == 4, "Expected 4 records for srv-B."
    assert srv_b[0]['timestamp'] == 100 and srv_b[0]['temp_celsius'] == 60.0 and srv_b[0]['cpu_load'] == 30.0
    assert srv_b[1]['timestamp'] == 110 and srv_b[1]['temp_celsius'] == 60.0 and srv_b[1]['cpu_load'] == 30.0
    assert srv_b[2]['timestamp'] == 120 and srv_b[2]['temp_celsius'] == 70.0 and srv_b[2]['cpu_load'] == 40.0
    assert srv_b[3]['timestamp'] == 130 and srv_b[3]['temp_celsius'] == 70.0 and srv_b[3]['cpu_load'] == 40.0
    conn.close()


def test_csv_export():
    """Test that the final_averages.csv file exists and contains the correct averages."""
    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} is missing."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames == ['server_id', 'avg_temp', 'avg_load'], f"Unexpected CSV headers: {reader.fieldnames}"
    assert len(rows) == 2, f"Expected 2 rows in CSV, found {len(rows)}."
    data = {row['server_id']: row for row in rows}
    assert 'srv-A' in data, "srv-A missing from CSV."
    assert 'srv-B' in data, "srv-B missing from CSV."
    assert float(data['srv-A']['avg_temp']) == 45.0, f"srv-A avg_temp incorrect: {data['srv-A']['avg_temp']}"
    assert float(data['srv-A']['avg_load']) == 15.0, f"srv-A avg_load incorrect: {data['srv-A']['avg_load']}"
    assert float(data['srv-B']['avg_temp']) == 65.0, f"srv-B avg_temp incorrect: {data['srv-B']['avg_temp']}"
    assert float(data['srv-B']['avg_load']) == 35.0, f"srv-B avg_load incorrect: {data['srv-B']['avg_load']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
