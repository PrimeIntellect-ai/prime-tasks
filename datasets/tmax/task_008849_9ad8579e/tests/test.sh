#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess
import time

import numpy as np
import pandas as pd
import pytest

RAW_DATA_PATH = '/home/user/raw_data.csv'
ETL_PATH = '/home/user/etl.py'
INFERENCE_PATH = '/home/user/inference.py'
PARQUET_PATH = '/home/user/processed_data.parquet'
REPORT_PATH = '/home/user/report.json'


def compute_expected_values():
    f1_vals = []
    f2_vals = []
    f3_vals = []

    with open(RAW_DATA_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            f1_vals.append(float(row['f1']))
            f2_vals.append(float(row['f2']))
            f3_vals.append(float(row['f3']))

    row_count = len(f1_vals)

    f1_min, f1_max = min(f1_vals), max(f1_vals)
    f2_min, f2_max = min(f2_vals), max(f2_vals)
    f3_min, f3_max = min(f3_vals), max(f3_vals)

    preds = []
    for i in range(row_count):
        f1_scaled = (f1_vals[i] - f1_min) / (f1_max - f1_min)
        f2_scaled = (f2_vals[i] - f2_min) / (f2_max - f2_min)
        f3_scaled = (f3_vals[i] - f3_min) / (f3_max - f3_min)
        pred = 0.5 * f1_scaled + 0.3 * f2_scaled - 0.2 * f3_scaled
        preds.append(pred)

    mean_pred = sum(preds) / row_count
    return row_count, round(mean_pred, 4)


def _column_reference(node, column):
    for child in ast.walk(node):
        if isinstance(child, ast.Subscript):
            sl = child.slice
            if isinstance(sl, ast.Constant) and sl.value == column:
                return True
    return False


def _weighted_term(node, coefficient, column):
    if not isinstance(node, ast.BinOp) or not isinstance(node.op, ast.Mult):
        return False
    pairs = ((node.left, node.right), (node.right, node.left))
    return any(
        isinstance(number, ast.Constant)
        and isinstance(number.value, (int, float))
        and float(number.value) == coefficient
        and _column_reference(value, column)
        for number, value in pairs
    )


def _is_inference_formula(node):
    return (
        isinstance(node, ast.BinOp)
        and isinstance(node.op, ast.Sub)
        and isinstance(node.left, ast.BinOp)
        and isinstance(node.left.op, ast.Add)
        and _weighted_term(node.left.left, 0.5, 'f1')
        and _weighted_term(node.left.right, 0.3, 'f2')
        and _weighted_term(node.right, 0.2, 'f3')
    )


def _contains_formula(node):
    return any(_is_inference_formula(child) for child in ast.walk(node))


def _validate_inference_source():
    with open(INFERENCE_PATH, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=INFERENCE_PATH)

    functions = {
        node.name: node
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }

    benchmark_loops = []
    for node in ast.walk(tree):
        if isinstance(node, ast.For) and isinstance(node.iter, ast.Call):
            func = node.iter.func
            is_range = (
                isinstance(func, ast.Name) and func.id == 'range'
            ) or (
                isinstance(func, ast.Attribute) and func.attr in ('range', 'arange')
            )
            if is_range and len(node.iter.args) == 1:
                arg = node.iter.args[0]
                if isinstance(arg, ast.Constant) and arg.value == 100:
                    benchmark_loops.append(node)

    assert benchmark_loops, 'inference.py must contain a loop that runs 100 times'

    performs_formula = False
    for loop in benchmark_loops:
        if _contains_formula(loop):
            performs_formula = True
            break
        called_names = {
            call.func.id
            for call in ast.walk(loop)
            if isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
        }
        if any(name in functions and _contains_formula(functions[name]) for name in called_names):
            performs_formula = True
            break

    assert performs_formula, (
        'The 100-run benchmark loop must perform the required '
        '0.5*f1 + 0.3*f2 - 0.2*f3 computation'
    )


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    for path in (ETL_PATH, INFERENCE_PATH):
        assert os.path.isfile(path), f'Required Python script is missing at {path}'
        with open(path, 'r', encoding='utf-8') as f:
            ast.parse(f.read(), filename=path)

    _validate_inference_source()
    raw_before = open(RAW_DATA_PATH, 'rb').read()

    for path in (PARQUET_PATH, REPORT_PATH):
        if os.path.lexists(path):
            os.remove(path)

    etl_result = subprocess.run(
        ['python3', ETL_PATH], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert etl_result.returncode == 0, f'etl.py failed:\n{etl_result.stderr}'
    assert open(RAW_DATA_PATH, 'rb').read() == raw_before, 'etl.py modified raw_data.csv'
    assert os.path.isfile(PARQUET_PATH), 'etl.py did not create processed_data.parquet'

    raw = pd.read_csv(RAW_DATA_PATH)
    actual = pd.read_parquet(PARQUET_PATH)
    assert list(actual.columns) == ['id', 'f1', 'f2', 'f3'], (
        f'Unexpected Parquet schema: {list(actual.columns)}'
    )
    assert len(actual) == len(raw), 'Parquet row count does not match raw_data.csv'
    assert actual['id'].tolist() == raw['id'].tolist(), 'Parquet id column was not preserved'
    for column in ('f1', 'f2', 'f3'):
        expected = (raw[column] - raw[column].min()) / (raw[column].max() - raw[column].min())
        np.testing.assert_allclose(
            actual[column].to_numpy(dtype=float), expected.to_numpy(dtype=float),
            rtol=1e-12, atol=1e-12,
            err_msg=f'Parquet column {column} is not correctly Min-Max scaled'
        )

    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    started = time.perf_counter()
    inference_result = subprocess.run(
        ['python3', INFERENCE_PATH], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    assert inference_result.returncode == 0, f'inference.py failed:\n{inference_result.stderr}'
    assert os.path.isfile(REPORT_PATH), 'inference.py did not create report.json'

    with open(REPORT_PATH, 'r') as f:
        report = json.load(f)
    avg = report.get('avg_time_ms')
    assert isinstance(avg, (int, float)) and not isinstance(avg, bool)
    assert math.isfinite(avg) and avg > 0
    assert avg == round(avg, 4), 'avg_time_ms must be rounded to 4 decimal places'
    assert avg <= elapsed_ms / 100.0, (
        'Reported average benchmark time is impossible relative to the script runtime'
    )


def test_parquet_file_exists():
    """Test that the processed Parquet file was created."""
    assert os.path.isfile(PARQUET_PATH), f"Processed Parquet file is missing at {PARQUET_PATH}"


def test_report_json_exists():
    """Test that the report JSON file was created."""
    assert os.path.isfile(REPORT_PATH), f"Report JSON file is missing at {REPORT_PATH}"


def test_report_json_contents():
    """Test that the report JSON contains the correct keys and values."""
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    expected_row_count, expected_mean_pred = compute_expected_values()

    assert "row_count" in report, "Key 'row_count' missing from report.json"
    assert "mean_pred" in report, "Key 'mean_pred' missing from report.json"
    assert "avg_time_ms" in report, "Key 'avg_time_ms' missing from report.json"
    assert set(report) == {'row_count', 'mean_pred', 'avg_time_ms'}, 'report.json must contain exactly the required keys'

    assert report["row_count"] == expected_row_count, f"Expected row_count to be {expected_row_count}, got {report['row_count']}"
    assert report["mean_pred"] == expected_mean_pred, f"Expected mean_pred to be {expected_mean_pred}, got {report['mean_pred']}"
    assert isinstance(report["avg_time_ms"], (int, float)), f"Expected avg_time_ms to be a number, got {type(report['avg_time_ms'])}"
    assert report["avg_time_ms"] >= 0, "Average time should be non-negative"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
