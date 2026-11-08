#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import random
import stat
import subprocess
import sys
from collections import defaultdict

SCRIPT = "/home/user/analyze.py"
INPUT = "/home/user/server_logs.csv"
OUTPUT = "/home/user/rolling_metrics.csv"


def assert_multiprocessing_used(tree):
    module_aliases = set()
    imported_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "multiprocessing" or alias.name.startswith("multiprocessing."):
                    module_aliases.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.module:
            if node.module == "multiprocessing" or node.module.startswith("multiprocessing."):
                for alias in node.names:
                    imported_names.add(alias.asname or alias.name)

    assert module_aliases or imported_names, \
        "analyze.py must import Python's multiprocessing module."

    process_apis = {"Pool", "Process", "get_context"}
    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in imported_names and func.id in process_apis:
            used = True
            break
        if isinstance(func, ast.Attribute) and func.attr in {"Pool", "Process"}:
            value = func.value
            while isinstance(value, ast.Attribute):
                value = value.value
            if isinstance(value, ast.Name) and value.id in module_aliases:
                used = True
                break
            if (isinstance(value, ast.Call) and isinstance(value.func, ast.Name)
                    and value.func.id in imported_names):
                used = True
                break

    assert used, \
        "analyze.py must use multiprocessing Pool, Process, or a multiprocessing context."


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"analyze.py failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did the script run?"


def expected_from_input(input_file):
    server_data = defaultdict(list)
    with open(input_file, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            server_data[row["server_id"]].append({
                "timestamp": int(row["timestamp"]),
                "cpu_usage": row["cpu_usage"],
            })

    expected_rows = []
    for server_id, records in server_data.items():
        records.sort(key=lambda x: x["timestamp"])
        last_cpu = 0.0
        cpu_history = []
        for rec in records:
            if rec["cpu_usage"] == "":
                cpu = last_cpu
            else:
                cpu = float(rec["cpu_usage"])
                last_cpu = cpu
            cpu_history.append(cpu)
            window = cpu_history[-3:]
            avg_cpu = sum(window) / len(window)
            expected_rows.append({
                "timestamp": str(rec["timestamp"]),
                "server_id": server_id,
                "rolling_cpu": f"{avg_cpu:.2f}",
            })

    expected_rows.sort(key=lambda x: (int(x["timestamp"]), x["server_id"]))
    return expected_rows


def assert_output_matches(input_file, output_file):
    expected_rows = expected_from_input(input_file)
    actual_rows = []
    with open(output_file, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["timestamp", "server_id", "rolling_cpu"], \
            f"Incorrect headers in {output_file}. Expected ['timestamp', 'server_id', 'rolling_cpu'], got {reader.fieldnames}"
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), \
        f"Row count mismatch in {output_file}. Expected {len(expected_rows)} rows, got {len(actual_rows)}."
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Mismatch at row {i+1} (excluding header). Expected {expected}, got {actual}."


def test_analyze_script_exists_uses_multiprocessing_and_runs():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), f"{SCRIPT} is empty."
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        raise AssertionError(f"{SCRIPT} is not valid Python: {exc}") from exc
    assert_multiprocessing_used(tree)

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_script()


def test_rolling_metrics_exists():
    """Test that the output CSV file exists."""
    file_path = "/home/user/rolling_metrics.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. Did the script run?"


def test_rolling_metrics_contents():
    """Test that the output CSV file has the correctly computed rolling metrics."""
    input_file = "/home/user/server_logs.csv"
    output_file = "/home/user/rolling_metrics.csv"
    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."
    assert_output_matches(input_file, output_file)


def test_script_on_unseen_multiline_input():
    original_input = open(INPUT, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
    rng = random.SystemRandom()
    base = rng.randrange(1800000000, 1900000000)
    a = rng.randrange(11, 80)
    b = rng.randrange(81, 150)
    c = rng.randrange(151, 220)
    rows = [
        [str(base + 4), "node-z", f"{a}.0", "late record"],
        [str(base + 1), "node-a", "", "first missing\ncontinued detail"],
        [str(base + 3), "node-z", "", "forward fill"],
        [str(base + 2), "node-a", f"{b}.0", "quoted message\nwith two\nnewlines"],
        [str(base + 1), "node-z", f"{c}.0", "start"],
        [str(base + 5), "node-a", "", "missing again"],
        [str(base + 2), "node-z", f"{a + 7}.0", "middle"],
        [str(base + 3), "node-a", f"{b + 9}.0", "known"],
        [str(base + 2), "node-m", "", "only missing first"],
        [str(base + 6), "node-z", f"{c + 5}.0", "fourth period"],
    ]

    try:
        with open(INPUT, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "server_id", "cpu_usage", "log_message"])
            writer.writerows(rows)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_script()
        assert_output_matches(INPUT, OUTPUT)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
