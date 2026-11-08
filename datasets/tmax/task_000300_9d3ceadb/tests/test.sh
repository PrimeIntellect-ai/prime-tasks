#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import time
import subprocess
from datetime import datetime, timezone

import pytest
import pandas as pd
import numpy as np

BASE = "/home/user/data_gen"
LOG_PATH = os.path.join(BASE, "experiment_log.json")
CSV_PATH = os.path.join(BASE, "synthetic_data.csv")
TRUE_MEAN = np.array([1.50, -2.00, 3.50])
TRUE_COV = np.array([
    [2.00, 0.40, -0.30],
    [0.40, 1.50, 0.20],
    [-0.30, 0.20, 3.00]
])
RUN_START = None
RUN_END = None

@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    """Require the submitted Go module to create fresh artifacts."""
    global RUN_START, RUN_END

    main_path = os.path.join(BASE, "main.go")
    module_path = os.path.join(BASE, "go.mod")
    assert os.path.isfile(main_path), f"Go source missing at {main_path}"
    assert os.path.isfile(module_path), f"Go module file missing at {module_path}"
    assert os.path.getsize(main_path) > 0, f"Go source is empty at {main_path}"

    for path in (LOG_PATH, CSV_PATH):
        if os.path.lexists(path):
            assert os.path.isfile(path) and not os.path.islink(path), f"Output path must be a regular file: {path}"
            os.remove(path)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env.setdefault("GOPATH", "/home/user/go")
    env.setdefault("GOCACHE", "/home/user/.cache/go-build")

    RUN_START = time.time()
    result = subprocess.run(
        ["go", "run", "."], cwd=BASE, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=180
    )
    RUN_END = time.time()
    assert result.returncode == 0, f"Submitted Go pipeline failed:\n{result.stdout}"

    for path in (LOG_PATH, CSV_PATH):
        assert os.path.isfile(path) and not os.path.islink(path), f"Go program did not create regular file {path}"
        assert os.path.getmtime(path) >= RUN_START - 2, f"Go program did not freshly generate {path}"


def _walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _contains_array(document, expected):
    for value in _walk(document):
        if not isinstance(value, list):
            continue
        try:
            candidate = np.asarray(value, dtype=float)
        except (TypeError, ValueError):
            continue
        if candidate.shape == expected.shape and np.allclose(candidate, expected, atol=1e-10, rtol=0):
            return True
    return False


def _parse_timestamp(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        stamp = float(value)
        if stamp > 1e12:
            stamp /= 1000.0
        return stamp if stamp > 1e8 else None
    if not isinstance(value, str):
        return None
    text = value.strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.timestamp()
    except ValueError:
        return None


def test_experiment_log_exists():
    """Check if the experiment log file exists."""
    log_path = "/home/user/data_gen/experiment_log.json"
    assert os.path.exists(log_path), f"Experiment log missing at {log_path}"
    assert os.path.isfile(log_path), f"Path {log_path} is not a file"

    # Try parsing it as JSON to ensure it's valid
    try:
        with open(log_path, 'r') as f:
            json.load(f)
    except json.JSONDecodeError:
        assert False, f"File {log_path} is not valid JSON"


def test_experiment_log_contents_and_timestamp():
    with open(LOG_PATH, "r") as f:
        document = json.load(f)

    assert _contains_array(document, TRUE_MEAN), "Experiment log does not contain the extracted mean vector"
    assert _contains_array(document, TRUE_COV), "Experiment log does not contain the extracted covariance matrix"

    timestamps = [_parse_timestamp(value) for value in _walk(document)]
    timestamps = [stamp for stamp in timestamps if stamp is not None]
    assert timestamps, "Experiment log does not contain a valid generation timestamp"
    assert any(RUN_START - 600 <= stamp <= RUN_END + 600 for stamp in timestamps), (
        "Experiment log does not contain a timestamp for this generation run"
    )


def test_synthetic_data_statistics():
    """Validate the generated synthetic dataset against the target statistics."""
    csv_path = "/home/user/data_gen/synthetic_data.csv"
    assert os.path.exists(csv_path), f"Synthetic data CSV missing at {csv_path}"

    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        assert False, f"Failed to read CSV at {csv_path}: {e}"

    assert len(df) == 50000, f"Expected 50000 rows in synthetic data, got {len(df)}"

    expected_cols = ['f1', 'f2', 'f3']
    for col in expected_cols:
        assert col in df.columns, f"Expected column '{col}' missing from CSV headers"

    # Ground truth parameters
    true_mean = np.array([1.50, -2.00, 3.50])
    true_cov = np.array([
        [2.00, 0.40, -0.30],
        [0.40, 1.50, 0.20],
        [-0.30, 0.20, 3.00]
    ])

    emp_mean = df[['f1', 'f2', 'f3']].mean().values
    emp_cov = df[['f1', 'f2', 'f3']].cov().values

    mean_err = np.max(np.abs(emp_mean - true_mean))
    cov_err = np.max(np.abs(emp_cov - true_cov))

    total_err = mean_err + cov_err
    threshold = 0.05

    assert total_err <= threshold, (
        f"Total error (max mean err + max cov err) is {total_err:.5f}, "
        f"which exceeds the threshold of {threshold}. "
        f"Mean err: {mean_err:.5f}, Cov err: {cov_err:.5f}"
    )


def test_samples_have_multivariate_normal_shape():
    """Check higher-order and tail behavior, not only engineered first two moments."""
    df = pd.read_csv(CSV_PATH)
    try:
        x = df[['f1', 'f2', 'f3']].to_numpy(dtype=float)
    except (TypeError, ValueError) as exc:
        pytest.fail(f"Sample columns are not numeric: {exc}")
    assert np.isfinite(x).all(), "Synthetic data contains non-finite values"

    chol = np.linalg.cholesky(TRUE_COV)
    z = np.linalg.solve(chol, (x - TRUE_MEAN).T).T
    directions = np.array([
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [1.0, 1.0, 1.0],
        [1.0, -2.0, 0.5],
        [-0.7, 0.2, 1.3],
    ])
    directions /= np.linalg.norm(directions, axis=1, keepdims=True)

    for direction in directions:
        projection = z @ direction
        centered = projection - projection.mean()
        variance = np.mean(centered ** 2)
        skew = np.mean(centered ** 3) / variance ** 1.5
        excess_kurtosis = np.mean(centered ** 4) / variance ** 2 - 3.0
        assert abs(skew) < 0.10, f"Projection has non-normal skewness {skew:.4f}"
        assert abs(excess_kurtosis) < 0.15, f"Projection has non-normal kurtosis {excess_kurtosis:.4f}"
        assert abs(np.mean(np.abs(projection) <= 1.0) - 0.682689) < 0.02, "Projection has incorrect normal central mass"
        assert abs(np.mean(np.abs(projection) <= 2.0) - 0.954500) < 0.015, "Projection has incorrect normal tail mass"

    squared_radius = np.sum(z * z, axis=1)
    assert abs(squared_radius.mean() - 3.0) < 0.08, "Mahalanobis radii do not match a 3-D normal"
    assert abs(squared_radius.var() - 6.0) < 0.35, "Mahalanobis radius variance is not chi-square(3)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
