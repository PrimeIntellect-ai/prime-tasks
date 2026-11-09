#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
import random
import pytest


def generate_expression_and_value(depth=0):
    if depth > 2:
        n = random.randint(1, 20)
        return str(n), n

    op = random.choice(['+', '-', '*', '/', 'SUM_SQ', 'MOD'])
    s1, v1 = generate_expression_and_value(depth + 1)
    s2, v2 = generate_expression_and_value(depth + 1)

    if op == '+':
        return f"({s1} + {s2})", v1 + v2
    elif op == '-':
        return f"({s1} - {s2})", v1 - v2
    elif op == '*':
        return f"({s1} * {s2})", v1 * v2
    elif op == '/':
        if v2 == 0:
            v2 = 1
            s2 = "1"
        # /app/vendor_eval rewrites '/' to Python '//'.
        return f"({s1} / {s2})", v1 // v2
    elif op == 'SUM_SQ':
        return f"SUM_SQ({s1}, {s2})", v1 * v1 + v2 * v2
    elif op == 'MOD':
        if v2 == 0:
            v2 = 1
            s2 = "1"
        # /app/vendor_eval implements MOD using Python's remainder semantics.
        return f"MOD({s1}, {s2})", v1 % v2


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_fast_eval_performance_and_accuracy():
    fast_eval_path = "/home/user/fast_eval.py"
    assert os.path.exists(fast_eval_path), f"Python script missing at {fast_eval_path}"

    hidden_input = "/tmp/hidden_eval.txt"
    hidden_output = "/tmp/fast_out.txt"

    random.seed(42)
    expected_results = []

    with open(hidden_input, "w") as f:
        for _ in range(10000):
            expr, val = generate_expression_and_value()
            f.write(f"{expr}\n")
            expected_results.append(val)

    start_time = time.time()
    result = subprocess.run(
        ["python3", fast_eval_path, hidden_input, hidden_output],
        capture_output=True,
        text=True
    )
    end_time = time.time()

    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    elapsed = end_time - start_time
    assert elapsed <= 1.0, f"Execution time {elapsed:.2f}s exceeded threshold of 1.0s"

    assert os.path.exists(hidden_output), f"Output file missing at {hidden_output}"

    actual_results = read_nonempty_lines(hidden_output)

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} outputs, got {len(actual_results)}"

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert str(actual) == str(expected), f"Mismatch at line {i+1}: expected {expected}, got {actual}"


def test_final_results_exist():
    final_expr = "/home/user/data/final_expressions.txt"
    results = "/home/user/data/results.txt"

    assert os.path.exists(final_expr), f"Patched file missing at {final_expr}"
    assert os.path.exists(results), f"Results file missing at {results}"
    assert os.path.isfile(final_expr), f"Patched path is not a file: {final_expr}"
    assert os.path.isfile(results), f"Results path is not a file: {results}"

    expected_expressions = [
        "1 + 2",
        "3 * 4",
        "10 / 2",
        "SUM_SQ(3, 4)",
        "MOD(10, 3)",
        "SUM_SQ(1, 1) + MOD(5, 2)",
    ]
    expected_results = ["3", "12", "5", "25", "1", "3"]

    assert read_nonempty_lines(final_expr) == expected_expressions, \
        "final_expressions.txt does not contain the correctly patched expressions"
    assert read_nonempty_lines(results) == expected_results, \
        "results.txt does not contain the correct vendor-compatible results"

    regenerated = "/tmp/regenerated_final_results.txt"
    run = subprocess.run(
        ["python3", "/home/user/fast_eval.py", final_expr, regenerated],
        capture_output=True,
        text=True,
    )
    assert run.returncode == 0, f"Script failed on final expressions:\n{run.stderr}"
    assert os.path.exists(regenerated), "Script did not create output for final expressions"
    assert read_nonempty_lines(regenerated) == expected_results, \
        "fast_eval.py does not correctly evaluate final_expressions.txt"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
