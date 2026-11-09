#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import math
import os
import sqlite3
import subprocess
import sys

import pytest

ANALYTICS_DIR = '/home/user/analytics'
DB_PATH = os.path.join(ANALYTICS_DIR, 'portfolio.db')
RESULT_PATH = os.path.join(ANALYTICS_DIR, 'result.txt')
ENGINE_PATH = os.path.join(ANALYTICS_DIR, 'engine.py')


def load_engine():
    assert os.path.exists(ENGINE_PATH), f"The file {ENGINE_PATH} is missing."
    if ANALYTICS_DIR not in sys.path:
        sys.path.insert(0, ANALYTICS_DIR)
    sys.modules.pop('engine', None)
    return importlib.import_module('engine')


def get_expected_rows():
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT t.id, t.amount, t.cashflow
            FROM trades t
            JOIN trade_events e ON t.id = e.trade_id
            WHERE e.status = 'SETTLED'
        """).fetchall()
    finally:
        conn.close()

    assert len(rows) == 1000, "Expected exactly 1000 SETTLED trades from the database."
    return rows


def get_expected_yield():
    rows = get_expected_rows()
    total_val = math.fsum(r[1] for r in rows)
    total_cashflow = sum(r[2] for r in rows)
    return total_cashflow / total_val


def test_00_run_job_executes_successfully_and_creates_result():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    proc = subprocess.run(
        [sys.executable, os.path.join(ANALYTICS_DIR, 'run_job.py')],
        cwd=ANALYTICS_DIR,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"run_job.py failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert "Job completed successfully." in proc.stdout, (
        f"The job did not report successful completion. stdout: {proc.stdout} stderr: {proc.stderr}"
    )
    assert os.path.exists(RESULT_PATH), "run_job.py did not create result.txt."


def test_result_file_exists_and_correct():
    assert os.path.exists(RESULT_PATH), (
        f"The result file was not found at {RESULT_PATH}. Did the job run successfully?"
    )

    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()

    assert content, "The result.txt file is empty."

    try:
        float(content)
    except ValueError:
        pytest.fail(f"Could not parse the contents of result.txt as a float. Found: {content}")

    expected_yield = get_expected_yield()
    expected_str = f"{expected_yield:.8f}"
    assert content == expected_str, (
        f"The computed yield in result.txt is incorrect. Expected {expected_str}, but found {content}."
    )


def test_fetch_trades_behavior():
    engine = load_engine()
    expected = get_expected_rows()
    actual = engine.fetch_trades()
    assert actual == expected, (
        "fetch_trades() must return exactly the trades joined to status 'SETTLED', "
        "without rows from other statuses or duplicate pending rows."
    )


def test_calculate_total_value_behavior():
    engine = load_engine()
    cases = [
        [1e16, 1.0, 1.0, -1e16],
        [1e20] + [0.1] * 10000 + [-1e20],
        [r[1] for r in get_expected_rows()],
    ]
    for amounts in cases:
        trades = [(i, value, 0.0) for i, value in enumerate(amounts)]
        expected = math.fsum(amounts)
        actual = engine.calculate_total_value(trades)
        assert actual == expected, (
            f"calculate_total_value() is not numerically stable: expected {expected!r}, got {actual!r}."
        )


def test_calculate_yield_behavior():
    engine = load_engine()
    cases = [
        (1_000_000.0, 40_000.0),
        (2_500_000.0, 75_000.0),
        (800_000.0, 60_000.0),
        (math.fsum(r[1] for r in get_expected_rows()), sum(r[2] for r in get_expected_rows())),
    ]
    for price, cashflow in cases:
        expected = cashflow / price
        actual = engine.calculate_yield(price, cashflow)
        assert math.isfinite(actual), "calculate_yield() returned a non-finite value."
        assert abs(actual - expected) < 1e-7, (
            f"calculate_yield({price}, {cashflow}) did not converge to {expected}; got {actual}."
        )


def test_engine_py_fixes():
    assert os.path.exists(ENGINE_PATH), f"The file {ENGINE_PATH} is missing."

    with open(ENGINE_PATH, 'r') as f:
        code = f.read()

    # Preserve the original source assertions.
    assert "SETTLED" in code, "The query does not appear to filter by 'SETTLED' status."
    assert "fsum" in code, "The calculate_total_value function does not appear to use math.fsum."
    assert "==" not in code.split("def calculate_yield")[1], (
        "The calculate_yield function still appears to use exact equality for convergence."
    )

    tree = ast.parse(code)
    functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
    assert {'fetch_trades', 'calculate_total_value', 'calculate_yield'} <= functions.keys()

    total_fn = functions['calculate_total_value']
    assert any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute) and node.func.attr == 'fsum')
            or (isinstance(node.func, ast.Name) and node.func.id == 'fsum')
        )
        for node in ast.walk(total_fn)
    ), "calculate_total_value() does not actively call fsum."

    yield_fn = functions['calculate_yield']
    has_tolerance_check = False
    for node in ast.walk(yield_fn):
        if not isinstance(node, ast.Compare) or len(node.ops) != 1 or not isinstance(node.ops[0], ast.Lt):
            continue
        if not (
            isinstance(node.left, ast.Call)
            and isinstance(node.left.func, ast.Name)
            and node.left.func.id == 'abs'
            and len(node.left.args) == 1
            and isinstance(node.left.args[0], ast.Name)
            and node.left.args[0].id == 'diff'
        ):
            continue
        comparator = node.comparators[0]
        if isinstance(comparator, ast.Constant) and isinstance(comparator.value, (int, float)):
            if comparator.value == 1e-7:
                has_tolerance_check = True
                break
    assert has_tolerance_check, "calculate_yield() must stop when abs(diff) < 1e-7."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
