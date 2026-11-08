#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

SCRIPT_PATH = "/home/user/analyze_covariances.py"
RESULTS_PATH = "/home/user/results.txt"


def test_script_exists():
    """Ensure the student created the script."""
    assert os.path.isfile(SCRIPT_PATH), f"Student script {SCRIPT_PATH} does not exist."


def test_script_executes_pipeline():
    """Execute the submitted script and verify that it performs the requested pipeline."""
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    audit_script = r'''
import math
import runpy
import sys
import numpy as np
import scipy.stats
import scipy.stats._kde

script_path = sys.argv[1]
events = []
randn_calls = []
cholesky_calls = []
svd_calls = []
fsum_calls = []
kde_calls = []
kde_evaluations = []

original_seed = np.random.seed
original_randn = np.random.randn
original_cholesky = np.linalg.cholesky
original_svd = np.linalg.svd
original_fsum = math.fsum
original_kde = scipy.stats.gaussian_kde


def audited_seed(value=None):
    events.append(("seed", value))
    return original_seed(value)


def audited_randn(*args):
    result = original_randn(*args)
    events.append(("randn", args))
    randn_calls.append((args, np.array(result, copy=True)))
    return result


def audited_cholesky(a, *args, **kwargs):
    result = original_cholesky(a, *args, **kwargs)
    cholesky_calls.append((np.array(a, copy=True), np.array(result, copy=True)))
    return result


def audited_svd(a, *args, **kwargs):
    result = original_svd(a, *args, **kwargs)
    saved_result = np.array(result, copy=True) if isinstance(result, np.ndarray) else result
    svd_calls.append((np.array(a, copy=True), args, dict(kwargs), saved_result))
    return result


def audited_fsum(values):
    saved_values = list(values)
    fsum_calls.append(saved_values)
    return original_fsum(saved_values)


class KDEProxy:
    def __init__(self, wrapped):
        self._wrapped = wrapped

    def _record(self, value):
        kde_evaluations.append(np.asarray(value).copy())

    def __call__(self, value):
        self._record(value)
        return self._wrapped(value)

    def evaluate(self, value):
        self._record(value)
        return self._wrapped.evaluate(value)

    def pdf(self, value):
        self._record(value)
        return self._wrapped.pdf(value)

    def __getattr__(self, name):
        return getattr(self._wrapped, name)


def audited_kde(dataset, *args, **kwargs):
    kde_calls.append(np.asarray(dataset).copy())
    return KDEProxy(original_kde(dataset, *args, **kwargs))


np.random.seed = audited_seed
np.random.randn = audited_randn
np.linalg.cholesky = audited_cholesky
np.linalg.svd = audited_svd
math.fsum = audited_fsum
scipy.stats.gaussian_kde = audited_kde
scipy.stats._kde.gaussian_kde = audited_kde

try:
    runpy.run_path(script_path, run_name="__main__")
except SystemExit as exc:
    assert exc.code in (None, 0), f"Submitted script exited with status {exc.code}"

seed_positions = [i for i, event in enumerate(events) if event == ("seed", 42)]
randn_candidates = [
    (i, result) for i, (args, result) in enumerate(randn_calls)
    if args == (2500, 5, 5) and result.shape == (2500, 5, 5)
]
assert seed_positions, "The script did not call numpy.random.seed(42)."
assert randn_candidates, "The script did not generate A with np.random.randn(2500, 5, 5)."

randn_event_positions = [
    i for i, event in enumerate(events)
    if event == ("randn", (2500, 5, 5))
]
assert min(seed_positions) < min(randn_event_positions), "The random seed was not set before generating A."
A = randn_candidates[0][1]
expected_M = A @ A.transpose(0, 2, 1) + 0.01 * np.eye(5)

matching_cholesky = [
    result for value, result in cholesky_calls
    if value.shape == expected_M.shape and np.array_equal(value, expected_M)
]
assert matching_cholesky, "The script did not compute the Cholesky decomposition of the requested M array."
L = matching_cholesky[0]

matching_svd = []
for value, args, kwargs, result in svd_calls:
    if value.shape != L.shape or not np.array_equal(value, L):
        continue
    if "compute_uv" in kwargs:
        compute_uv = kwargs["compute_uv"]
    elif len(args) >= 2:
        compute_uv = args[1]
    else:
        compute_uv = True
    if compute_uv is False and isinstance(result, np.ndarray):
        matching_svd.append(result)
assert matching_svd, "The script did not compute singular values of L with compute_uv=False."
singular_values = matching_svd[0]
max_s = singular_values[:, 0]
expected_sorted = sorted(max_s.tolist())

matching_fsum = [
    values for values in fsum_calls
    if len(values) == 2500 and values == expected_sorted
]
assert matching_fsum, "The script did not pass the ascending singular values to math.fsum()."
assert all(a < b for a, b in zip(expected_sorted, expected_sorted[1:])), "The singular values were not strictly ascending."

assert any(
    data.shape == max_s.shape and np.array_equal(data, max_s)
    for data in kde_calls
), "The script did not fit gaussian_kde to the unsorted largest singular values."
assert any(
    value.size == 1 and float(value.reshape(-1)[0]) == 6.0
    for value in kde_evaluations
), "The script did not evaluate the KDE at x = 6.0."
'''

    completed = subprocess.run(
        ["python3", "-c", audit_script, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, (
        "The submitted script failed execution or did not perform the requested pipeline:\n"
        + completed.stdout
    )
    assert os.path.isfile(RESULTS_PATH), f"Executing {SCRIPT_PATH} did not create {RESULTS_PATH}."


def test_results_file_content():
    """Compute the expected output and verify results.txt matches exactly."""
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."

    truth_script = """
import numpy as np
from scipy.stats import gaussian_kde
import math

np.random.seed(42)
A = np.random.randn(2500, 5, 5)
M = A @ A.transpose(0, 2, 1) + 0.01 * np.eye(5)

L = np.linalg.cholesky(M)
s = np.linalg.svd(L, compute_uv=False)
max_s = s[:, 0]

sorted_max_s = sorted(max_s.tolist())
exact_sum = math.fsum(sorted_max_s)
stable_mean = exact_sum / 2500.0

kde = gaussian_kde(max_s)
kde_val = kde(6.0)[0]

print(f"Stable Mean: {stable_mean:.6f}")
print(f"KDE at 6.0: {kde_val:.6f}")
"""
    try:
        expected_output = subprocess.check_output(
            ["python3", "-c", truth_script],
            text=True,
            stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to compute expected truth values. Error:\n{e.output}"

    with open(RESULTS_PATH, "r") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), (
        f"Contents of {RESULTS_PATH} do not match the expected output.\n"
        f"Expected:\n{expected_output.strip()}\n"
        f"Actual:\n{actual_output.strip()}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
