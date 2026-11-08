#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import runpy
import subprocess
import sys
import tempfile
import time
import uuid

import numpy as np
import pytest
from scipy import stats

SCRIPT_PATH = "/home/user/filter.py"
CORR_THRESHOLD = 0.75
P_THRESHOLD = 0.01


def expected_status(data):
    d = data.shape[1]
    if d > 1:
        corr = np.corrcoef(data, rowvar=False)
        off_diag = np.abs(corr[np.triu_indices(d, 1)])
        if np.any(off_diag > CORR_THRESHOLD):
            return 1
    pvalues = np.asarray(stats.ttest_1samp(data, popmean=0.0, axis=0).pvalue)
    if np.any(pvalues < P_THRESHOLD):
        return 1
    return 0


def run_filter(path, timeout=5):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    return result.returncode


def centered_low_corr(rng, n=1000, d=5):
    for _ in range(100):
        data = rng.normal(size=(n, d))
        data -= data.mean(axis=0, keepdims=True)
        if expected_status(data) == 0:
            return data
    raise AssertionError("Could not generate an acceptable array")


def exact_corr_case(rng, rho, n=1000):
    x = rng.normal(size=n)
    x -= x.mean()
    z = rng.normal(size=n)
    z -= z.mean()
    z -= x * (np.dot(x, z) / np.dot(x, x))
    z *= np.linalg.norm(x) / np.linalg.norm(z)
    y = rho * x + np.sqrt(1.0 - rho * rho) * z
    return np.column_stack((x, y))


def exact_p_case(rng, target_p, n=1000, d=4):
    data = centered_low_corr(rng, n=n, d=d)
    residual = data[:, 0]
    residual -= residual.mean()
    residual /= residual.std(ddof=1)
    t_value = stats.t.ppf(1.0 - target_p / 2.0, df=n - 1)
    data[:, 0] = residual + t_value / np.sqrt(n)
    return data


def test_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "/home/user/filter.py does not exist."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), "Clean corpus dir missing"
    assert os.path.isdir(evil_dir), "Evil corpus dir missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.npy')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.npy')]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    bypassed_evil = []
    modified_clean = []

    for f in clean_files:
        if run_filter(f) != 0:
            modified_clean.append(os.path.basename(f))

    for f in evil_files:
        if run_filter(f) == 0:
            bypassed_evil.append(os.path.basename(f))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_randomized_unlabeled_inputs():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    root = tempfile.mkdtemp(prefix="npycheck_")

    accepted = centered_low_corr(rng)

    mean_bad = centered_low_corr(rng)
    mean_bad[:, 3] += 0.18

    corr_bad = centered_low_corr(rng)
    corr_bad[:, 1] = 0.9 * corr_bad[:, 0] + 0.2 * rng.normal(size=corr_bad.shape[0])

    both_bad = centered_low_corr(rng)
    both_bad[:, 2] = -0.92 * both_bad[:, 0] + 0.15 * rng.normal(size=both_bad.shape[0])
    both_bad[:, 4] += 0.2

    cases = [
        accepted,
        mean_bad,
        corr_bad,
        both_bad,
        exact_corr_case(rng, 0.74),
        exact_corr_case(rng, 0.76),
        exact_p_case(rng, 0.011),
        exact_p_case(rng, 0.009),
    ]

    failures = []
    for data in cases:
        path = os.path.join(root, uuid.uuid4().hex + ".npy")
        np.save(path, data)
        expected = expected_status(data)
        actual = run_filter(path)
        if actual != expected:
            failures.append(f"{os.path.basename(path)} expected exit {expected}, got {actual}")

    assert not failures, " | ".join(failures)


def test_processing_time_under_200ms():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    root = tempfile.mkdtemp(prefix="speedcheck_")
    samples = []
    for _ in range(5):
        data = centered_low_corr(rng)
        path = os.path.join(root, uuid.uuid4().hex + ".npy")
        np.save(path, data)
        samples.append(path)

    harness = os.path.join(root, "runner.py")
    result_path = os.path.join(root, "result.json")
    with open(harness, "w") as f:
        f.write(r'''import json
import runpy
import sys
import time
import numpy
import scipy.stats

script, input_path, output_path = sys.argv[1:4]
sys.argv = [script, input_path]
status = 0
start = time.perf_counter()
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    status = 0 if exc.code is None else exc.code
except BaseException as exc:
    status = "exception:" + repr(exc)
elapsed = time.perf_counter() - start
with open(output_path, "w") as out:
    json.dump({"status": status, "elapsed": elapsed}, out)
''')

    elapsed = []
    for path in samples:
        if os.path.exists(result_path):
            os.unlink(result_path)
        proc = subprocess.run(
            ["python3", harness, SCRIPT_PATH, path, result_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0 and os.path.isfile(result_path), "Timing harness could not execute filter.py"
        with open(result_path) as f:
            outcome = json.load(f)
        assert outcome["status"] == 0, f"Benchmark input was not accepted: {outcome['status']}"
        elapsed.append(float(outcome["elapsed"]))

    median = float(np.median(elapsed))
    assert median < 0.200, f"Median processing time was {median * 1000:.1f}ms, exceeding 200ms"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
