#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import json
import os
import secrets
import sqlite3
import stat
import subprocess
from collections import Counter, defaultdict

import pytest

PIPELINE = "/home/user/pipeline.py"
DATA_DIR = "/home/user/data"
DB_PATH = "/home/user/metrics.db"
JSON_PATH = "/home/user/anomalies.json"
LOG_PATH = "/home/user/pipeline.log"

EXPECTED_ROWS = []


def _install_unseen_input():
    global EXPECTED_ROWS

    os.makedirs(DATA_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(DATA_DIR, "*.csv")):
        os.remove(path)

    # Values vary per verifier run so precomputed output artifacts cannot pass.
    base = secrets.randbelow(31) + 20
    dates_and_cpus = [
        ("2024-01-01", [base - 1, base + 1]),
        ("2024-01-03", [1.5 * base - 0.25, 1.5 * base + 0.25]),
        ("2024-02-10", [3 * base - 2, 3 * base + 2]),
        ("2024-02-11", [2 * base - 1, 2 * base + 1]),
    ]

    rows = []
    sequence = 0
    for date, cpus in dates_and_cpus:
        for hour, cpu in zip((9, 17), cpus):
            sequence += 1
            rows.append({
                "timestamp": f"{date}T{hour:02d}:{sequence:02d}:00Z",
                "cpu_usage": str(cpu),
                "memory_mb": str(700 + sequence * 37),
                "network_tx_kb": str(110 + sequence * 19.5),
            })

    # Use nonstandard CSV filenames and distribute dates across files.
    groups = [rows[0:3], rows[3:6], rows[6:]]
    for index, group in enumerate(groups):
        path = os.path.join(DATA_DIR, f"verification_batch_{index}_{secrets.token_hex(4)}.csv")
        with open(path, "w", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=["timestamp", "cpu_usage", "memory_mb", "network_tx_kb"],
            )
            writer.writeheader()
            writer.writerows(group)

    EXPECTED_ROWS = [
        (
            row["timestamp"],
            float(row["cpu_usage"]),
            float(row["memory_mb"]),
            float(row["network_tx_kb"]),
        )
        for row in rows
    ]


def _run_pipeline_from_clean_state():
    for path in (DB_PATH, JSON_PATH, LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["python3", PIPELINE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.py exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(PIPELINE), f"Pipeline script not found at {PIPELINE}"
    assert stat.S_ISREG(os.stat(PIPELINE).st_mode), f"{PIPELINE} is not a regular file"

    with open(PIPELINE, "r", encoding="utf-8") as handle:
        source = handle.read()
    try:
        ast.parse(source, filename=PIPELINE)
    except SyntaxError as exc:
        pytest.fail(f"pipeline.py is not valid Python: {exc}")

    _install_unseen_input()
    _run_pipeline_from_clean_state()
    yield


def test_pipeline_contains_a_dag_resolver():
    with open(PIPELINE, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=PIPELINE)

    required_tasks = {"init_db", "load_data", "detect_anomalies", "export_results"}
    string_literals = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    assert required_tasks <= string_literals, "pipeline.py does not define all required DAG tasks"

    semantic = ("dag", "topolog", "resolv", "orchestrat")
    resolver_found = False

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            args = [arg.arg for arg in node.args.posonlyargs + node.args.args]
            if args and args[0] in ("self", "cls"):
                args = args[1:]
            named_as_resolver = any(token in node.name.lower() for token in semantic)
            has_algorithmic_flow = any(isinstance(child, (ast.For, ast.While)) for child in ast.walk(node))
            if named_as_resolver and len(args) >= 2 and has_algorithmic_flow:
                resolver_found = True

        if isinstance(node, ast.ClassDef) and any(token in node.name.lower() for token in semantic):
            methods = [child for child in node.body if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef))]
            init_methods = [method for method in methods if method.name == "__init__"]
            accepts_tasks_and_dependencies = any(
                len([arg for arg in method.args.args if arg.arg not in ("self", "cls")]) >= 2
                for method in init_methods
            )
            has_algorithmic_flow = any(
                isinstance(child, (ast.For, ast.While))
                for method in methods for child in ast.walk(method)
            )
            if accepts_tasks_and_dependencies and has_algorithmic_flow:
                resolver_found = True

    assert resolver_found, (
        "pipeline.py must implement a DAG/topological resolver that accepts tasks and "
        "dependencies and traverses them"
    )


def test_database_exists_and_populated():
    db_path = DB_PATH
    assert os.path.exists(db_path), f"Database not found at {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='server_metrics';")
    table = cursor.fetchone()
    assert table is not None, "Table 'server_metrics' does not exist in the database."

    # Preserve the original row-count assertion.
    cursor.execute("SELECT COUNT(*) FROM server_metrics;")
    db_row_count = cursor.fetchone()[0]

    csv_files = glob.glob("/home/user/data/*.csv")
    csv_row_count = 0
    for f in csv_files:
        with open(f, "r") as csvfile:
            reader = csv.reader(csvfile)
            next(reader, None)
            csv_row_count += sum(1 for _ in reader)

    assert db_row_count == csv_row_count, f"Expected {csv_row_count} rows in server_metrics, found {db_row_count}."

    # Validate the complete required schema, not merely the table name.
    cursor.execute("PRAGMA table_info(server_metrics)")
    schema = [(row[1], row[2].upper()) for row in cursor.fetchall()]
    assert schema == [
        ("timestamp", "TEXT"),
        ("cpu_usage", "REAL"),
        ("memory_mb", "REAL"),
        ("network_tx_kb", "REAL"),
    ], f"Unexpected server_metrics schema: {schema}"

    # Validate every loaded value from the verifier-generated CSV files.
    cursor.execute(
        "SELECT timestamp, cpu_usage, memory_mb, network_tx_kb FROM server_metrics"
    )
    actual_rows = cursor.fetchall()
    assert Counter(actual_rows) == Counter(EXPECTED_ROWS), (
        f"Database rows do not exactly match the CSV input. Got: {actual_rows}"
    )
    conn.close()


def test_anomalies_json_matches_truth():
    json_path = JSON_PATH
    assert os.path.exists(json_path), f"Anomalies JSON not found at {json_path}"

    # Recompute truth from CSVs.
    csv_files = glob.glob("/home/user/data/*.csv")
    daily_cpu = defaultdict(list)

    for f in csv_files:
        with open(f, "r") as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                date = row["timestamp"].split("T")[0]
                daily_cpu[date].append(float(row["cpu_usage"]))

    daily_avg = {date: sum(cpus) / len(cpus) for date, cpus in daily_cpu.items()}
    sorted_dates = sorted(daily_avg.keys())

    expected_anomalies = []
    for i in range(1, len(sorted_dates)):
        prev_date = sorted_dates[i - 1]
        curr_date = sorted_dates[i]
        if daily_avg[curr_date] > 1.5 * daily_avg[prev_date]:
            expected_anomalies.append(curr_date)

    with open(json_path, "r") as jf:
        try:
            data = json.load(jf)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {json_path}")

    assert set(data.keys()) == {"anomalies"}, "JSON must contain exactly the 'anomalies' key."
    assert data["anomalies"] == expected_anomalies, f"Expected anomalies {expected_anomalies}, got {data['anomalies']}."


def test_pipeline_log_format_and_content():
    log_path = LOG_PATH
    assert os.path.exists(log_path), f"Log file not found at {log_path}"

    expected_sequence = [
        "INFO:DAG:Starting task init_db",
        "INFO:DAG:Completed task init_db",
        "INFO:DAG:Starting task load_data",
        "INFO:DAG:Completed task load_data",
        "INFO:DAG:Starting task detect_anomalies",
        "INFO:DAG:Completed task detect_anomalies",
        "INFO:DAG:Starting task export_results",
        "INFO:DAG:Completed task export_results",
    ]

    with open(log_path, "r") as lf:
        log_lines = [line.strip() for line in lf if line.strip()]

    dag_lines = [line for line in log_lines if line.startswith("INFO:DAG:")]
    assert dag_lines == expected_sequence, "Log lines do not match the expected DAG execution sequence."
    assert log_lines == expected_sequence, "The log contains lines that do not use the required exact format."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
