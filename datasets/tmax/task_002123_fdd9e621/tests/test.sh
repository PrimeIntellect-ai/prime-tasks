#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import random
import subprocess

import pytest

SCRIPT = "/home/user/pipeline_test.py"
INPUT = "/home/user/input.csv"
OUTPUT = "/home/user/output.csv"
METRICS = "/home/user/metrics.json"


def test_01_pipeline_script_exists():
    """Keep the original script-existence assertion."""
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} does not exist."


def test_02_output_csv_content():
    """Keep the original exact assertion for the supplied input."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."

    with open(OUTPUT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "id,value,category",
        "1,12.5,X",
        "3,8.1,Z",
        "5,0.0,X",
    ]
    assert lines == expected_lines, (
        f"Content of {OUTPUT} is incorrect. Expected {expected_lines}, but got {lines}."
    )


def test_03_metrics_json_content():
    """Keep the original metrics assertions and require exactly three typed keys."""
    assert os.path.isfile(METRICS), f"Metrics file {METRICS} was not created."

    with open(METRICS, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS} is not valid JSON.")

    expected_metrics = {
        "original_rows": 5,
        "valid_rows": 3,
        "schema_passed": True,
    }
    for key, expected_value in expected_metrics.items():
        assert key in metrics, f"Key '{key}' is missing from {METRICS}."
        assert metrics[key] == expected_value, (
            f"Value for '{key}' in {METRICS} is incorrect. "
            f"Expected {expected_value}, got {metrics[key]}."
        )

    assert set(metrics) == set(expected_metrics), (
        f"{METRICS} must contain exactly {sorted(expected_metrics)}, got {sorted(metrics)}."
    )
    assert type(metrics["original_rows"]) is int
    assert type(metrics["valid_rows"]) is int
    assert type(metrics["schema_passed"]) is bool


def test_04_script_defines_and_uses_pandera_schema():
    """Verify that the artifact contains an actual pandera DataFrameSchema workflow."""
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imports_pandera = False
    schema_names = {"DataFrameSchema"}
    column_names = {"Column"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pandera" or alias.name.startswith("pandera."):
                    imports_pandera = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == "pandera" or node.module.startswith("pandera.")):
                imports_pandera = True
                for alias in node.names:
                    if alias.name == "DataFrameSchema":
                        schema_names.add(alias.asname or alias.name)
                    if alias.name == "Column":
                        column_names.add(alias.asname or alias.name)

    assert imports_pandera, "pipeline_test.py must import pandera."

    def called_name(call):
        if not isinstance(call, ast.Call):
            return None
        if isinstance(call.func, ast.Name):
            return call.func.id
        if isinstance(call.func, ast.Attribute):
            return call.func.attr
        return None

    schema_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and called_name(node) in schema_names
    ]
    column_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and called_name(node) in column_names
    ]
    assert schema_calls, "pipeline_test.py must explicitly construct a pandera DataFrameSchema."
    assert len(column_calls) >= 3, "The DataFrameSchema must define the three required columns."

    literals = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    assert {"id", "value", "category"}.issubset(literals), (
        "The pandera schema must explicitly cover id, value, and category."
    )

    assigned_schema_names = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if isinstance(value, ast.Call) and called_name(value) in schema_names:
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        assigned_schema_names.add(target.id)

    uses_validate = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "validate"
        for node in ast.walk(tree)
    )
    calls_schema_object = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id in assigned_schema_names
        for node in ast.walk(tree)
    )
    assert uses_validate or calls_schema_object, (
        "The constructed pandera schema must be used to validate the cleaned dataframe."
    )

    subprocess.run(
        ["python3", "-c", "import pandas, pandera"],
        check=True,
        capture_output=True,
        text=True,
    )


def _run_case(rows):
    with open(INPUT, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "value", "category"])
        writer.writeheader()
        writer.writerows(rows)

    for path in (OUTPUT, METRICS):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Pipeline failed on a verifier-generated input.\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "Running the pipeline did not create output.csv."
    assert os.path.isfile(METRICS), "Running the pipeline did not create metrics.json."

    expected = [
        row for row in rows
        if float(row["value"]) >= 0.0 and row["category"] in {"X", "Y", "Z"}
    ]

    with open(OUTPUT, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "value", "category"], (
            "output.csv must have exactly the required columns and no index column."
        )
        actual = list(reader)

    assert len(actual) == len(expected)
    for got, want in zip(actual, expected):
        assert int(got["id"]) == int(want["id"])
        assert float(got["value"]) == pytest.approx(float(want["value"]))
        assert got["category"] == want["category"]

    with open(METRICS, encoding="utf-8") as f:
        metrics = json.load(f)
    assert set(metrics) == {"original_rows", "valid_rows", "schema_passed"}
    assert type(metrics["original_rows"]) is int
    assert type(metrics["valid_rows"]) is int
    assert type(metrics["schema_passed"]) is bool
    assert metrics == {
        "original_rows": len(rows),
        "valid_rows": len(expected),
        "schema_passed": True,
    }


def test_05_pipeline_executes_correctly_on_unseen_inputs():
    """Execute the submitted artifact on randomized inputs and derive expected results."""
    paths = (INPUT, OUTPUT, METRICS)
    backups = {
        path: (open(path, "rb").read() if os.path.exists(path) else None)
        for path in paths
    }
    rng = random.SystemRandom()
    base = rng.randrange(10000, 90000)
    a = rng.randrange(101, 9999) / 100.0
    b = rng.randrange(101, 9999) / 100.0
    c = rng.randrange(101, 9999) / 100.0

    cases = [
        [
            {"id": base, "value": f"{a:.2f}", "category": "X"},
            {"id": base + 1, "value": f"{-b:.2f}", "category": "Y"},
            {"id": base + 2, "value": "0.0", "category": "Z"},
            {"id": base + 3, "value": f"{c:.2f}", "category": "W"},
            {"id": base + 4, "value": f"{b:.2f}", "category": "Y"},
        ],
        [
            {"id": base + 20, "value": f"{c:.2f}", "category": "Z"},
            {"id": base + 21, "value": f"{a:.2f}", "category": "Y"},
            {"id": base + 22, "value": f"{-c:.2f}", "category": "Q"},
            {"id": base + 23, "value": "0.0", "category": "X"},
        ],
    ]

    try:
        for rows in cases:
            _run_case(rows)
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
