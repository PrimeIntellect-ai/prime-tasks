#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import subprocess
import pytest

PIPELINE = "/home/user/pipeline.py"
OUTPUT = "/home/user/unified.jsonl"
TRACE = "/home/user/dag_trace.txt"
CSV_INPUT = "/home/user/raw_logs/cluster_a.csv"
JSON_INPUT = "/home/user/raw_logs/cluster_b.json"
TASKS = {"extract_a", "extract_b", "transform_impute", "load_results"}


def read_jsonl(file_path):
    actual_data = []
    with open(file_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON on line {line_num} of {file_path}: {line}")
    return actual_data


def assert_trace_valid(file_path):
    assert os.path.isfile(file_path), f"The file {file_path} is missing."
    with open(file_path, "r") as f:
        tasks = [line.strip() for line in f if line.strip()]

    assert "extract_a" in tasks, "Task 'extract_a' is missing from dag_trace.txt"
    assert "extract_b" in tasks, "Task 'extract_b' is missing from dag_trace.txt"
    assert "transform_impute" in tasks, "Task 'transform_impute' is missing from dag_trace.txt"
    assert "load_results" in tasks, "Task 'load_results' is missing from dag_trace.txt"

    idx_a = tasks.index("extract_a")
    idx_b = tasks.index("extract_b")
    idx_transform = tasks.index("transform_impute")
    idx_load = tasks.index("load_results")

    assert idx_a < idx_transform, "'extract_a' must run before 'transform_impute'."
    assert idx_b < idx_transform, "'extract_b' must run before 'transform_impute'."
    assert idx_transform < idx_load, "'transform_impute' must run before 'load_results'."


def test_unified_jsonl_exists_and_correct():
    assert os.path.isfile(OUTPUT), f"The file {OUTPUT} is missing."

    expected_data = [
        {"timestamp": 1000, "cpu": 10.0, "memory": 100},
        {"timestamp": 2000, "cpu": 15.0, "memory": 100},
        {"timestamp": 3000, "cpu": 20.0, "memory": 120},
        {"timestamp": 4000, "cpu": 25.0, "memory": 130},
        {"timestamp": 5000, "cpu": 30.0, "memory": 140},
        {"timestamp": 6000, "cpu": 35.0, "memory": 140}
    ]

    actual_data = read_jsonl(OUTPUT)
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("timestamp") == expected["timestamp"], f"Record {i} timestamp mismatch: expected {expected['timestamp']}, got {actual.get('timestamp')}"
        assert actual.get("cpu") == expected["cpu"], f"Record {i} cpu mismatch: expected {expected['cpu']}, got {actual.get('cpu')}"
        assert actual.get("memory") == expected["memory"], f"Record {i} memory mismatch: expected {expected['memory']}, got {actual.get('memory')}"
        assert isinstance(actual["timestamp"], int), f"Record {i} timestamp must be an int."
        assert isinstance(actual["cpu"], float), f"Record {i} cpu must be a float."
        assert isinstance(actual["memory"], int), f"Record {i} memory must be an int."


def test_dag_trace_exists_and_valid():
    assert_trace_valid(TRACE)


def test_pipeline_script_exists():
    assert os.path.isfile(PIPELINE), f"The file {PIPELINE} is missing."


def _identifiers(node):
    result = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Name):
            result.add(child.id)
        elif isinstance(child, ast.Constant) and isinstance(child.value, str):
            result.add(child.value)
    return result


def _has_executor_logic(tree):
    loop_types = (ast.For, ast.While, ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)
    for fn in (n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name not in TASKS):
        descendants = list(ast.walk(fn))
        if not any(isinstance(n, loop_types) for n in descendants):
            continue

        loop_vars = set()
        for loop in descendants:
            if isinstance(loop, (ast.For, ast.comprehension)):
                target = loop.target
                loop_vars.update(n.id for n in ast.walk(target) if isinstance(n, ast.Name))

        for call in (n for n in descendants if isinstance(n, ast.Call)):
            if isinstance(call.func, ast.Subscript):
                return True
            if isinstance(call.func, ast.Name) and call.func.id in loop_vars:
                return True
            if isinstance(call.func, ast.Name) and call.func.id == fn.name:
                return True
            if isinstance(call.func, ast.Attribute) and call.func.attr == fn.name:
                return True
    return False


def test_pipeline_contains_dag_tasks_dependencies_and_executor():
    with open(PIPELINE, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=PIPELINE)
    except SyntaxError as exc:
        pytest.fail(f"pipeline.py is not valid Python: {exc}")

    defined = {
        n.name for n in ast.walk(tree)
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert TASKS <= defined, f"Missing required task functions: {sorted(TASKS - defined)}"

    relation_sets = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Dict, ast.List, ast.Tuple, ast.Set, ast.Call)):
            relation_sets.append(_identifiers(node))
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for decorator in node.decorator_list:
                relation_sets.append(_identifiers(decorator) | {node.name})

    assert any({"extract_a", "extract_b", "transform_impute"} <= names for names in relation_sets), \
        "The DAG must represent transform_impute as dependent on both extraction tasks."
    assert any({"transform_impute", "load_results"} <= names for names in relation_sets), \
        "The DAG must represent load_results as dependent on transform_impute."
    assert _has_executor_logic(tree), \
        "No task executor that iterates/resolves tasks or dependencies was found."


def test_zz_pipeline_executes_on_changed_inputs():
    with open(CSV_INPUT, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "cpu_usage", "memory_usage"])
        writer.writerow([100, 10.0, 50])
        writer.writerow([500, "", ""])
        writer.writerow([1100, 32.0, 80])
        writer.writerow([1500, "", ""])

    with open(JSON_INPUT, "w") as f:
        json.dump([
            {"t": 300, "cpu": None, "mem": 60},
            {"t": 800, "cpu": 26.0, "mem": None},
            {"t": 1900, "cpu": 48.0, "mem": 100}
        ], f)

    for path in (OUTPUT, TRACE):
        if os.path.exists(path):
            os.remove(path)

    completed = subprocess.run(
        ["python3", PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20
    )
    assert completed.returncode == 0, \
        f"pipeline.py failed when executed.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert os.path.isfile(OUTPUT), "Executing pipeline.py did not generate unified.jsonl."
    assert os.path.isfile(TRACE), "Executing pipeline.py did not generate dag_trace.txt."

    expected = [
        {"timestamp": 100, "cpu": 10.0, "memory": 50},
        {"timestamp": 300, "cpu": 14.6, "memory": 60},
        {"timestamp": 500, "cpu": 19.1, "memory": 60},
        {"timestamp": 800, "cpu": 26.0, "memory": 60},
        {"timestamp": 1100, "cpu": 32.0, "memory": 80},
        {"timestamp": 1500, "cpu": 40.0, "memory": 80},
        {"timestamp": 1900, "cpu": 48.0, "memory": 100}
    ]
    actual = read_jsonl(OUTPUT)
    assert actual == expected, f"Pipeline output for changed inputs was incorrect: {actual}"

    for i, record in enumerate(actual):
        assert set(record) == {"timestamp", "cpu", "memory"}, f"Record {i} has incorrect keys."
        assert type(record["timestamp"]) is int, f"Record {i} timestamp must be an int."
        assert type(record["cpu"]) is float, f"Record {i} cpu must be a float."
        assert type(record["memory"]) is int, f"Record {i} memory must be an int."

    assert_trace_valid(TRACE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
