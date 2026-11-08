#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import secrets
import subprocess
import sys
import tempfile
import importlib.util
import pytest


def load_stats_module():
    stats_path = "/home/user/stats.py"
    assert os.path.exists(stats_path), f"File {stats_path} is missing."
    spec = importlib.util.spec_from_file_location("submitted_stats", stats_path)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as e:
        pytest.fail(f"Failed to import {stats_path}: {e}")
    assert hasattr(module, "StreamingStats"), "StreamingStats class is missing from stats.py."
    return module


def test_mre_exists_and_valid():
    mre_path = "/home/user/mre.py"
    assert os.path.exists(mre_path), f"File {mre_path} is missing. You must create the MRE script."

    with open(mre_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "StreamingStats" in content, "mre.py must instantiate and use the StreamingStats class."
    assert "100000000.1" in content or "try:" in content or "except" in content, \
        "mre.py should contain the minimal sequence of floats to reproduce the issue and handle the exception."

    try:
        tree = ast.parse(content, filename=mre_path)
    except SyntaxError as e:
        pytest.fail(f"mre.py is not valid Python: {e}")

    expected = [100000000.1, 100000000.1, 100000000.1]
    literal_sequences = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)):
            try:
                value = ast.literal_eval(node)
            except Exception:
                continue
            if isinstance(value, (list, tuple)) and all(isinstance(x, float) for x in value):
                literal_sequences.append(list(value))
    assert expected in literal_sequences, \
        "mre.py must contain the hardcoded minimal float sequence [100000000.1, 100000000.1, 100000000.1]."

    # Execute the MRE with the original defective StreamingStats implementation.
    # This checks that it really instantiates the class, feeds only the minimal
    # sequence, calls get_stddev(), catches the crash, and prints the exception.
    runner = r'''
import math
import runpy
import sys
import types

_instances = []
class StreamingStats:
    def __init__(self):
        self.sum = 0.0
        self.sum_sq = 0.0
        self.count = 0
        self.values = []
        self.get_calls = 0
        _instances.append(self)
    def update(self, x):
        self.values.append(x)
        self.sum += x
        self.sum_sq += x * x
        self.count += 1
    def get_stddev(self):
        self.get_calls += 1
        if self.count < 2:
            return 0.0
        mean = self.sum / self.count
        variance = (self.sum_sq - self.count * mean * mean) / (self.count - 1)
        return math.sqrt(variance)

fake_stats = types.ModuleType("stats")
fake_stats.StreamingStats = StreamingStats
sys.modules["stats"] = fake_stats
runpy.run_path("/home/user/mre.py", run_name="__main__")
assert len(_instances) == 1, "MRE must instantiate StreamingStats exactly once"
assert _instances[0].values == [100000000.1, 100000000.1, 100000000.1], \
    "MRE must feed only the minimal crashing sequence"
assert _instances[0].get_calls >= 1, "MRE never requested the standard deviation"
'''
    result = subprocess.run(
        [sys.executable, "-c", runner], text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, \
        f"mre.py did not catch the historical crash or did not use the minimal sequence:\n{result.stdout}{result.stderr}"
    printed = result.stdout + result.stderr
    assert "math domain" in printed.lower() or "valueerror" in printed.lower(), \
        "mre.py must print the resulting ValueError/math domain exception."


def test_stats_fixed_no_domain_error():
    stats_module = load_stats_module()

    stats = stats_module.StreamingStats()
    problematic_sequence = [100000000.1, 100000000.1, 100000000.1]
    for val in problematic_sequence:
        stats.update(val)

    try:
        stddev = stats.get_stddev()
    except ValueError as e:
        pytest.fail(f"stats.py still raises ValueError on problematic sequence: {e}. The variance calculation is not fixed.")
    except Exception as e:
        pytest.fail(f"stats.py raised an unexpected error: {e}")
    assert stddev >= 0.0, "Standard deviation should be non-negative."
    assert math.isfinite(stddev), "Standard deviation should be finite."


def test_stats_computes_real_standard_deviations():
    stats_module = load_stats_module()

    # Answers are derived independently. Randomized moderate-scale cases prevent
    # a constant-zero or fixed-table implementation from passing.
    cases = [
        [1.0, 2.0, 4.0, 8.0],
        [-12.5, 3.25, 7.75, 20.0, -1.5],
        [1.0e8, 1.0e8 + 1000.0, 1.0e8 - 500.0, 1.0e8 + 250.0],
    ]
    rng = secrets.SystemRandom()
    for _ in range(5):
        values = [rng.uniform(-10000.0, 10000.0) for _ in range(rng.randrange(4, 12))]
        cases.append(values)

    for values in cases:
        stats = stats_module.StreamingStats()
        for value in values:
            stats.update(value)
        try:
            actual = stats.get_stddev()
        except Exception as e:
            pytest.fail(f"get_stddev failed for valid values {values!r}: {e}")
        expected = math.stdev(values)
        assert isinstance(actual, (int, float)), "get_stddev() must return a number."
        assert math.isfinite(actual) and actual >= 0.0, "Standard deviation must be finite and non-negative."
        assert math.isclose(actual, expected, rel_tol=1e-8, abs_tol=1e-9), \
            f"Incorrect standard deviation for {values!r}: got {actual}, expected {expected}."


def test_success_txt_exists_and_complete():
    success_path = "/home/user/success.txt"
    assert os.path.exists(success_path), f"File {success_path} is missing. You must redirect the successful output here."

    with open(success_path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, "success.txt is empty."
    content = "".join(lines)
    # Preserve the original assertions.
    assert "Row 7:" in content, "success.txt does not contain the output for the final row. The script may have crashed."
    assert "val=100000000.1" in content, "success.txt does not contain the expected value for the final row."

    # Run the actual application and require success.txt to be its complete,
    # unmodified stdout rather than a fabricated subset.
    result = subprocess.run(
        [sys.executable, "/home/user/process.py"],
        cwd="/home/user", text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, f"process.py failed:\n{result.stdout}{result.stderr}"
    with open(success_path, "r") as f:
        saved = f.read()
    assert saved == result.stdout, \
        "success.txt must contain the complete exact output of python3 /home/user/process.py."

    with open("/home/user/sensor_data.csv", newline="") as f:
        rows = list(csv.reader(f))[1:]
    output_lines = result.stdout.splitlines()
    assert len(output_lines) == max(0, len(rows) - 1), \
        "process.py did not emit one output line for every data row after the first sample."
    for index, (line, row) in enumerate(zip(output_lines, rows[1:]), start=2):
        prefix = f"Row {index}: val={float(row[1])}, stddev="
        assert line.startswith(prefix), f"Unexpected or incomplete process output line: {line!r}"
        try:
            value = float(line[len(prefix):])
        except ValueError:
            pytest.fail(f"Invalid standard deviation in process output: {line!r}")
        assert math.isfinite(value) and value >= 0.0, \
            f"Invalid standard deviation in process output: {line!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
