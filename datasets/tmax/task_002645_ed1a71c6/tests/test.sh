#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import uuid

import numpy as np
import pytest

CLEAN_CORPUS_DIR = "/app/clean_corpus"
EVIL_CORPUS_DIR = "/app/evil_corpus"
SCRIPT_PATH = "/home/user/etl_filter.py"


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(path)],
        capture_output=True,
        timeout=15,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Directory {CLEAN_CORPUS_DIR} missing."
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, f"No JSON files found in {CLEAN_CORPUS_DIR}."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run(["python3", SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Directory {EVIL_CORPUS_DIR} missing."
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, f"No JSON files found in {EVIL_CORPUS_DIR}."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run(["python3", SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed/accepted. Offending files: {', '.join(failed_files)}")


def bootstrap_lower(values):
    np.random.seed(42)
    means = []
    array = np.asarray(values, dtype=float)
    for _ in range(1000):
        sample = np.random.choice(array, size=len(array), replace=True)
        means.append(np.mean(sample))
    return float(np.percentile(means, 2.5))


def correlated_metrics(rho, feat_c):
    # These centered, orthogonal vectors produce Pearson correlation rho.
    x = np.asarray([-3.0, -1.0, 1.0, 3.0])
    z = math.sqrt(5.0) * np.asarray([1.0, -1.0, -1.0, 1.0])
    y = rho * x + math.sqrt(1.0 - rho * rho) * z
    offset_a = random.SystemRandom().uniform(-20.0, 20.0)
    offset_b = random.SystemRandom().uniform(-20.0, 20.0)
    return [
        {"feat_A": float(a + offset_a), "feat_B": float(b + offset_b), "feat_C": float(c)}
        for a, b, c in zip(x, y, feat_c)
    ]


def shifted_bootstrap_values(target_lower):
    rng = random.SystemRandom()
    for _ in range(100):
        base = [
            -1.2 + rng.uniform(-0.15, 0.15),
            -0.4 + rng.uniform(-0.15, 0.15),
            0.1 + rng.uniform(-0.15, 0.15),
            0.5 + rng.uniform(-0.15, 0.15),
            1.0 + rng.uniform(-0.15, 0.15),
            1.4 + rng.uniform(-0.15, 0.15),
            2.0 + rng.uniform(-0.15, 0.15),
        ]
        shift = target_lower - bootstrap_lower(base)
        values = [v + shift for v in base]
        actual = bootstrap_lower(values)
        if min(values) < 0.0 < max(values) and ((actual >= 0.0) == (target_lower >= 0.0)):
            return values
    raise AssertionError("Could not construct a mixed-sign bootstrap fixture")


def make_linear_metrics(count, feat_c):
    offset = random.SystemRandom().uniform(-50.0, 50.0)
    return [
        {
            "feat_A": float(i + offset),
            "feat_B": float(3.0 * i - offset),
            "feat_C": float(feat_c[i]),
        }
        for i in range(count)
    ]


def test_novel_randomized_inputs(tmp_path):
    rng = random.SystemRandom()
    positive_boot = shifted_bootstrap_values(rng.uniform(0.01, 0.03))
    negative_boot = shifted_bootstrap_values(rng.uniform(-0.03, -0.01))

    cases = []

    # split(" ") retains the empty token between consecutive spaces.
    cases.append((
        {"text": "one  two three", "metrics": make_linear_metrics(4, [0.2, 0.3, 0.4, 0.5])},
        0,
    ))

    # Shape mismatch with otherwise passing numerical data.
    cases.append((
        {"text": "one two three", "metrics": make_linear_metrics(4, [0.2, 0.3, 0.4, 0.5])},
        1,
    ))

    # Exercise correlations on both sides of the threshold using constructed data.
    cases.append((
        {"text": "one two three four", "metrics": correlated_metrics(0.76, [0.2] * 4)},
        0,
    ))
    cases.append((
        {"text": "one two three four", "metrics": correlated_metrics(0.74, [0.2] * 4)},
        1,
    ))

    # Mixed-sign feat_C cases whose answers are derived with the specified
    # NumPy seed, resample count, means, and percentile calculation.
    pos_metrics = make_linear_metrics(len(positive_boot), positive_boot)
    neg_metrics = make_linear_metrics(len(negative_boot), negative_boot)
    cases.append((
        {"text": " ".join(f"p{i}" for i in range(len(pos_metrics))), "metrics": pos_metrics},
        0 if bootstrap_lower(positive_boot) >= 0.0 else 1,
    ))
    cases.append((
        {"text": " ".join(f"n{i}" for i in range(len(neg_metrics))), "metrics": neg_metrics},
        0 if bootstrap_lower(negative_boot) >= 0.0 else 1,
    ))

    rng.shuffle(cases)
    failures = []
    for payload, expected_code in cases:
        path = tmp_path / f"{uuid.uuid4().hex}.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        result = run_validator(path)
        if result.returncode != expected_code:
            failures.append(
                f"{path.name}: expected exit {expected_code}, got {result.returncode}; "
                f"stderr={result.stderr.decode(errors='replace')[:300]!r}"
            )

    if failures:
        pytest.fail("Novel validation cases failed:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
