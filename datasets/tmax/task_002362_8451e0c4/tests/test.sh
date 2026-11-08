#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pathlib
import subprocess
import sys
import tempfile
import pytest

PARALLEL_STARTS = 0


def compute_expected_results(csv_path):
    data = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            func = row['Function']
            size = float(row['DataSize'])
            time = float(row['ExecutionTime'])

            if func not in data:
                data[func] = {'sizes': [], 'times': [], 'times_1000': []}

            data[func]['sizes'].append(size)
            data[func]['times'].append(time)

            if size == 1000.0:
                data[func]['times_1000'].append(time)

    results = {}
    for func, vals in data.items():
        # Linear regression slope
        x = vals['sizes']
        y = vals['times']
        n = len(x)
        mean_x = sum(x) / n
        mean_y = sum(y) / n
        cov = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
        var_x = sum((xi - mean_x) ** 2 for xi in x)
        slope = cov / var_x

        # Lognorm fit for DataSize == 1000
        # For scipy.stats.lognorm.fit with floc=0, the MLE parameters are:
        # shape = std(log(data)) (with ddof=0)
        # scale = exp(mean(log(data)))
        t1000 = vals['times_1000']
        log_t = [math.log(t) for t in t1000]
        n1000 = len(log_t)
        mean_log = sum(log_t) / n1000
        var_log = sum((lt - mean_log) ** 2 for lt in log_t) / n1000
        shape = math.sqrt(var_log)
        scale = math.exp(mean_log)

        results[func] = {
            "slope": round(slope, 4),
            "lognorm_shape": round(shape, 4),
            "lognorm_scale": round(scale, 4)
        }

    return results


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global PARALLEL_STARTS

    script_path = "/home/user/analyze_perf.py"
    output_path = "/home/user/perf_summary.json"
    assert os.path.isfile(script_path), "The script /home/user/analyze_perf.py does not exist or is not a regular file."

    if os.path.exists(output_path):
        os.remove(output_path)

    audit_dir = tempfile.mkdtemp(prefix="perf_mp_audit_")
    marker_path = os.path.join(audit_dir, "starts.log")
    sitecustomize = r'''
import os
try:
    import multiprocessing.process as _mp_process
    _original_start = _mp_process.BaseProcess.start

    def _audited_start(self, *args, **kwargs):
        marker = os.environ.get("MP_AUDIT_LOG")
        if marker:
            with open(marker, "a") as f:
                f.write("start\n")
        return _original_start(self, *args, **kwargs)

    _mp_process.BaseProcess.start = _audited_start
except Exception:
    pass
'''
    pathlib.Path(audit_dir, "sitecustomize.py").write_text(sitecustomize)

    env = os.environ.copy()
    env["MP_AUDIT_LOG"] = marker_path
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = audit_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")

    try:
        proc = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("/home/user/analyze_perf.py did not finish within 120 seconds.")

    assert proc.returncode == 0, (
        "/home/user/analyze_perf.py exited with an error.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )

    if os.path.exists(marker_path):
        with open(marker_path, "r") as f:
            PARALLEL_STARTS = sum(1 for line in f if line.strip() == "start")


def test_script_exists():
    assert os.path.exists("/home/user/analyze_perf.py"), "The script /home/user/analyze_perf.py does not exist."


def test_output_json_exists():
    assert os.path.exists("/home/user/perf_summary.json"), "The output file /home/user/perf_summary.json does not exist."


def test_output_json_correctness():
    csv_path = "/home/user/perf_logs.csv"
    json_path = "/home/user/perf_summary.json"

    assert os.path.exists(csv_path), f"Input file {csv_path} is missing."
    assert os.path.exists(json_path), f"Output file {json_path} is missing."

    expected = compute_expected_results(csv_path)

    with open(json_path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/perf_summary.json is not valid JSON.")

    assert isinstance(actual, dict), "The top-level JSON structure should be a dictionary."

    expected_keys = set(expected.keys())
    actual_keys = set(actual.keys())
    assert expected_keys == actual_keys, f"Expected keys {expected_keys}, but got {actual_keys}."

    for func in expected:
        expected_metrics = expected[func]
        actual_metrics = actual[func]

        assert isinstance(actual_metrics, dict), f"The value for '{func}' should be a dictionary."

        for metric, expected_val in expected_metrics.items():
            assert metric in actual_metrics, f"Missing metric '{metric}' for function '{func}'."
            actual_val = actual_metrics[metric]
            assert isinstance(actual_val, (int, float)), f"Metric '{metric}' for '{func}' should be a number."

            # Allow a small floating-point tolerance just in case, though rounding to 4 decimals should match
            diff = abs(expected_val - actual_val)
            assert diff <= 1e-4, f"Mismatch in {metric} for {func}: expected {expected_val}, got {actual_val}."


def test_multiprocessing_used():
    script_path = "/home/user/analyze_perf.py"
    if os.path.exists(script_path):
        with open(script_path, 'r') as f:
            content = f.read()
            assert "multiprocessing" in content or "ProcessPoolExecutor" in content or "Pool" in content, \
                "The script does not appear to use the multiprocessing module."


def test_multiple_worker_processes_started():
    assert PARALLEL_STARTS >= 2, (
        "The executed script did not start at least two multiprocessing worker processes; "
        "the functions do not appear to have been analyzed in parallel."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
