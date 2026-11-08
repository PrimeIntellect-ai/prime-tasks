#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import py_compile
import random
import stat
import subprocess
import sys

import numpy as np
import pytest
from scipy import stats

SCRIPT_PATH = "/home/user/evaluate_etl.py"
JSON_PATH = "/home/user/benchmark_results.json"
TRANSFORM_PATH = "/home/user/transform_step.py"
LOG_PATH = "/tmp/transform_invocations.jsonl"


def test_00_execute_and_validate_evaluation():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing. You need to create it."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"The path {SCRIPT_PATH} must be a regular file."
    py_compile.compile(SCRIPT_PATH, doraise=True)

    rng = random.SystemRandom()
    one_thread = [1.00 + rng.uniform(-0.06, 0.06) for _ in range(20)]
    four_thread = [0.70 + rng.uniform(-0.06, 0.06) for _ in range(20)]

    with open(TRANSFORM_PATH, "rb") as f:
        original_transform = f.read()
    original_mode = os.stat(TRANSFORM_PATH).st_mode

    stub = f'''import fcntl
import json
import os
import sys

LOG_PATH = {LOG_PATH!r}
VALUES = {{
    "1": {one_thread!r},
    "4": {four_thread!r},
}}
omp = os.environ.get("OMP_NUM_THREADS")
openblas = os.environ.get("OPENBLAS_NUM_THREADS")
key = omp if omp == openblas and omp in VALUES else "invalid:" + repr((omp, openblas))

with open(LOG_PATH, "a+", encoding="utf-8") as log:
    fcntl.flock(log.fileno(), fcntl.LOCK_EX)
    log.seek(0)
    previous = [json.loads(line) for line in log if line.strip()]
    index = sum(item == key for item in previous)
    log.seek(0, os.SEEK_END)
    log.write(json.dumps(key) + "\\n")
    log.flush()
    if key not in VALUES or index >= len(VALUES[key]):
        print("invalid benchmark invocation", file=sys.stderr)
        raise SystemExit(3)
    value = VALUES[key][index]

print(value)
'''

    try:
        with open(TRANSFORM_PATH, "w", encoding="utf-8") as f:
            f.write(stub)
        os.chmod(TRANSFORM_PATH, original_mode)

        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)

        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert completed.returncode == 0, (
            f"evaluate_etl.py failed with exit code {completed.returncode}.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )

        assert os.path.isfile(LOG_PATH), "The evaluation script never executed transform_step.py."
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            invocations = [json.loads(line) for line in f if line.strip()]
        assert len(invocations) == 40, f"Expected exactly 40 benchmark executions, got {len(invocations)}."
        assert invocations.count("1") == 20, (
            "Expected exactly 20 executions with OMP_NUM_THREADS=1 and OPENBLAS_NUM_THREADS=1."
        )
        assert invocations.count("4") == 20, (
            "Expected exactly 20 executions with OMP_NUM_THREADS=4 and OPENBLAS_NUM_THREADS=4."
        )
        assert set(invocations) == {"1", "4"}, "A benchmark execution used incorrect thread variables."

        assert os.path.isfile(JSON_PATH), f"The file {JSON_PATH} was not produced by evaluate_etl.py."
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            results = json.load(f)

        expected_keys = {"mean_diff", "t_statistic", "p_value", "reject_null"}
        assert set(results) == expected_keys
        assert isinstance(results["mean_diff"], float)
        assert isinstance(results["t_statistic"], float)
        assert isinstance(results["p_value"], float)
        assert isinstance(results["reject_null"], bool)

        expected_mean_diff = float(np.mean(one_thread) - np.mean(four_thread))
        expected_t, expected_p = stats.ttest_ind(one_thread, four_thread, equal_var=False)
        expected_t = float(expected_t)
        expected_p = float(expected_p)

        assert math.isfinite(results["mean_diff"])
        assert math.isfinite(results["t_statistic"])
        assert math.isfinite(results["p_value"])
        assert results["mean_diff"] == pytest.approx(expected_mean_diff, rel=1e-6, abs=1e-8)
        assert results["t_statistic"] == pytest.approx(expected_t, rel=1e-6, abs=1e-8)
        assert results["p_value"] == pytest.approx(expected_p, rel=1e-6, abs=1e-8)
        assert results["reject_null"] is (expected_p < 0.05)
    finally:
        with open(TRANSFORM_PATH, "wb") as f:
            f.write(original_transform)
        os.chmod(TRANSFORM_PATH, original_mode)


def test_benchmark_results_exists():
    json_path = "/home/user/benchmark_results.json"
    assert os.path.exists(json_path), f"The file {json_path} does not exist. Did you run your evaluate_etl.py script?"
    assert os.path.isfile(json_path), f"The path {json_path} is not a file."


def test_benchmark_results_content():
    json_path = "/home/user/benchmark_results.json"
    if not os.path.exists(json_path):
        pytest.skip(f"{json_path} is missing.")

    with open(json_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    expected_keys = {"mean_diff", "t_statistic", "p_value", "reject_null"}
    actual_keys = set(results.keys())
    assert actual_keys == expected_keys, f"Expected keys {expected_keys}, but got {actual_keys}."

    assert isinstance(results["mean_diff"], float), "The value for 'mean_diff' must be a float."
    assert isinstance(results["t_statistic"], float), "The value for 't_statistic' must be a float."
    assert isinstance(results["p_value"], float), "The value for 'p_value' must be a float."
    assert isinstance(results["reject_null"], bool), "The value for 'reject_null' must be a boolean."

    assert 0.0 <= results["p_value"] <= 1.0, f"The 'p_value' ({results['p_value']}) must be between 0.0 and 1.0."


def test_evaluate_etl_script_exists():
    script_path = "/home/user/evaluate_etl.py"
    assert os.path.exists(script_path), f"The script {script_path} is missing. You need to create it."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
