#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess
import textwrap
import pytest

PIPELINE_SH = "/home/user/run_pipeline.sh"
VARIANCE_PY = "/home/user/variance_test.py"
REPORT_PATH = "/home/user/report.json"
PYTHON_BIN = "/home/user/venv/bin/python"


def test_scripts_exist_and_executable():
    """Verify that the required scripts exist and run_pipeline.sh is executable."""
    assert os.path.isfile(PIPELINE_SH), f"{PIPELINE_SH} does not exist."
    assert os.path.isfile(VARIANCE_PY), f"{VARIANCE_PY} does not exist."

    st = os.stat(PIPELINE_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PIPELINE_SH} is not executable."


def test_execute_pipeline():
    """Execute the required wrapper as the unprivileged user and require a fresh report."""
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", PIPELINE_SH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "The executed pipeline did not create /home/user/report.json."


def test_venv_exists():
    """Verify that the virtual environment was created and contains Python."""
    assert os.path.isfile(PYTHON_BIN), "Python executable not found in /home/user/venv/bin/python. Was the venv created?"


def get_ground_truth():
    """Compute the ground truth errors using the venv's numpy."""
    script = r'''
import numpy as np
import json

rng = np.random.RandomState(42)
x = rng.normal(loc=1e7, scale=2.5, size=100000).astype(np.float32)

x64 = x.astype(np.float64)
true_var = np.var(x64)

naive_var = np.mean(x**2) - np.mean(x)**2
naive_error = abs(naive_var - true_var)

count = 0
mean = 0.0
M2 = 0.0
for val in x:
    count += 1
    delta = val - mean
    mean += delta / count
    delta2 = val - mean
    M2 += delta * delta2
welford_var = M2 / count
welford_error = abs(welford_var - true_var)

print(json.dumps({"naive_error": float(naive_error), "welford_error": float(welford_error)}))
'''
    result = subprocess.run(
        [PYTHON_BIN, "-c", script],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        pytest.fail(f"Failed to run ground truth script using venv python. Error: {result.stderr}")
    return json.loads(result.stdout)


def load_and_validate_report(path):
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not valid JSON.")

    expected_keys = {"naive_error", "welford_error", "welford_time_ci_low", "welford_time_ci_high"}
    assert set(report.keys()) == expected_keys, f"report.json keys {set(report.keys())} do not match expected {expected_keys}."

    for key in expected_keys:
        assert isinstance(report[key], (int, float)), f"Value for {key} must be a number."
        assert math.isfinite(report[key]), f"Value for {key} must be finite."
    return report


def test_report_json_content():
    """Verify the contents of the report produced by the real wrapper execution."""
    report = load_and_validate_report(REPORT_PATH)

    ci_low = report["welford_time_ci_low"]
    ci_high = report["welford_time_ci_high"]
    assert ci_low > 0, "welford_time_ci_low must be greater than 0."
    assert ci_high > 0, "welford_time_ci_high must be greater than 0."
    assert ci_low < ci_high, "welford_time_ci_low must be less than welford_time_ci_high."

    truth = get_ground_truth()

    naive_diff = abs(report["naive_error"] - truth["naive_error"])
    assert naive_diff <= 0.01 * truth["naive_error"], \
        f"naive_error {report['naive_error']} is not within 1% of expected {truth['naive_error']}."

    welford_diff = abs(report["welford_error"] - truth["welford_error"])
    assert welford_diff <= 1e-3, \
        f"welford_error {report['welford_error']} is not within 1e-3 of expected {truth['welford_error']}."


def test_exact_timing_and_bootstrap_work():
    """Run variance_test.py with a deterministic clock and audited RNG usage."""
    original_report = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            original_report = f.read()

    audit_script = r'''
import json
import math
import os
import runpy
import sys
import time
import numpy as np

TARGET = os.path.realpath("/home/user/variance_test.py")
REPORT = "/home/user/report.json"
original_random_state = np.random.RandomState
random_state_seeds = []
resample_sets = 0
all_replacement = True
perf_calls = 0
welford_calls = 0

class AuditedRandomState:
    def __init__(self, seed):
        self.inner = original_random_state(seed)

    def normal(self, *args, **kwargs):
        return self.inner.normal(*args, **kwargs)

    def choice(self, a, size=None, replace=True, p=None):
        global resample_sets, all_replacement
        result = self.inner.choice(a, size=size, replace=replace, p=p)
        shape = np.asarray(result).shape
        if shape and shape[-1] == 100:
            resample_sets += int(np.prod(shape[:-1])) if len(shape) > 1 else 1
            all_replacement = all_replacement and bool(replace)
        return result

    def randint(self, low, high=None, size=None, dtype=int):
        global resample_sets
        result = self.inner.randint(low, high=high, size=size, dtype=dtype)
        shape = np.asarray(result).shape
        upper = high if high is not None else low
        lower = low if high is not None else 0
        if lower == 0 and upper == 100 and shape and shape[-1] == 100:
            resample_sets += int(np.prod(shape[:-1])) if len(shape) > 1 else 1
        return result

    def __getattr__(self, name):
        return getattr(self.inner, name)


def random_state_factory(seed=None):
    random_state_seeds.append(seed)
    return AuditedRandomState(seed)


def fake_perf_counter():
    global perf_calls
    call = perf_calls
    perf_calls += 1
    iteration = call // 2
    base = iteration * 0.01
    if call % 2:
        return base + 0.001 + iteration * 0.000001
    return base


def profiler(frame, event, arg):
    global welford_calls
    if event == "call" and os.path.realpath(frame.f_code.co_filename) == TARGET and frame.f_code.co_name == "welford_variance":
        welford_calls += 1
    return profiler

np.random.RandomState = random_state_factory
time.perf_counter = fake_perf_counter
sys.setprofile(profiler)
try:
    runpy.run_path(TARGET, run_name="__main__")
finally:
    sys.setprofile(None)

with open(REPORT, "r") as f:
    report = json.load(f)

durations = np.array([0.001 + i * 0.000001 for i in range(100)], dtype=float)
rng = original_random_state(42)
bootstrap_means = np.array([
    np.mean(rng.choice(durations, size=100, replace=True))
    for _ in range(1000)
])
expected_low, expected_high = np.percentile(bootstrap_means, [2.5, 97.5])

print("AUDIT_RESULT=" + json.dumps({
    "perf_calls": perf_calls,
    "welford_calls": welford_calls,
    "random_state_seeds": random_state_seeds,
    "resample_sets": resample_sets,
    "all_replacement": all_replacement,
    "actual_low": report["welford_time_ci_low"],
    "actual_high": report["welford_time_ci_high"],
    "expected_low": float(expected_low),
    "expected_high": float(expected_high),
}))
'''

    try:
        result = subprocess.run(
            [PYTHON_BIN, "-c", audit_script],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f"Instrumented execution of variance_test.py failed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        marker_lines = [line for line in result.stdout.splitlines() if line.startswith("AUDIT_RESULT=")]
        assert marker_lines, f"Instrumented execution produced no audit result. stdout:\n{result.stdout}"
        audit = json.loads(marker_lines[-1].split("=", 1)[1])
    finally:
        if original_report is not None:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

    assert audit["perf_calls"] == 200, \
        f"Expected exactly 100 separately timed runs (200 perf_counter calls), got {audit['perf_calls']} calls."
    assert audit["welford_calls"] == 101, \
        f"Expected one result calculation plus 100 timed welford_variance calls, got {audit['welford_calls']} calls."
    assert audit["random_state_seeds"].count(42) >= 2, \
        "RandomState(42) must be used independently for data generation and bootstrap resampling."
    assert audit["resample_sets"] == 1000, \
        f"Expected exactly 1000 bootstrap resamples of 100 timings, got {audit['resample_sets']}."
    assert audit["all_replacement"], "Bootstrap sampling must use replacement."
    assert math.isclose(audit["actual_low"], audit["expected_low"], rel_tol=0, abs_tol=1e-12), \
        f"Bootstrap CI lower bound is incorrect: got {audit['actual_low']}, expected {audit['expected_low']}."
    assert math.isclose(audit["actual_high"], audit["expected_high"], rel_tol=0, abs_tol=1e-12), \
        f"Bootstrap CI upper bound is incorrect: got {audit['actual_high']}, expected {audit['expected_high']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
