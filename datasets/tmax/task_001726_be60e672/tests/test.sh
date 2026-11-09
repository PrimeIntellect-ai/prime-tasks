#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess
import sys
import tempfile
import uuid

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/filter_dataset.py"


def test_filter_dataset_script_exists():
    """Ensure the user created the required script."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_adversarial_corpus_evaluation():
    """Retain evaluation against the originally supplied corpus."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, f"No clean CSV files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil CSV files found in {evil_dir}"

    clean_failures = []
    for cf in clean_files:
        try:
            result = subprocess.run(
                ["python", SCRIPT_PATH, cf],
                capture_output=True,
                text=True,
                timeout=15,
            )
            if result.stdout.strip() != "ACCEPT":
                clean_failures.append(os.path.basename(cf))
        except subprocess.TimeoutExpired:
            clean_failures.append(f"{os.path.basename(cf)} (Timeout)")
        except Exception as exc:
            clean_failures.append(f"{os.path.basename(cf)} (Error: {exc})")

    evil_failures = []
    for ef in evil_files:
        try:
            result = subprocess.run(
                ["python", SCRIPT_PATH, ef],
                capture_output=True,
                text=True,
                timeout=15,
            )
            if result.stdout.strip() != "REJECT":
                evil_failures.append(os.path.basename(ef))
        except subprocess.TimeoutExpired:
            evil_failures.append(f"{os.path.basename(ef)} (Timeout)")
        except Exception as exc:
            evil_failures.append(f"{os.path.basename(ef)} (Error: {exc})")

    error_msg = []
    if evil_failures:
        error_msg.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failures)
        )
    if clean_failures:
        error_msg.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failures)
        )
    if error_msg:
        pytest.fail(" | ".join(error_msg))


def bootstrap_p95(values):
    values = np.asarray(values, dtype=float)
    rng = np.random.RandomState(42)
    means = [
        np.mean(rng.choice(values, size=len(values), replace=True))
        for _ in range(1000)
    ]
    return np.percentile(means, 95)


def expected_result(frame):
    frame = frame.copy()
    frame.columns = [str(name).strip() for name in frame.columns]
    if (frame["temperature"] == 999.9).any():
        return "REJECT"
    if frame["status"].isna().any():
        return "REJECT"
    pressures = frame["pressure"].to_numpy(dtype=float)
    threshold = bootstrap_p95(pressures)
    if np.max(pressures) > threshold + 10:
        return "REJECT"
    return "ACCEPT"


def make_frame(rng, n, pressure):
    return pd.DataFrame(
        {
            "temperature": rng.uniform(15.0, 35.0, n),
            "status": rng.choice(["active", "inactive", "maintenance"], n),
            "pressure": np.asarray(pressure, dtype=float),
        }
    )


def pressure_with_gap(base, target_gap):
    """Find a final maximum whose bootstrap gap is near the requested value."""
    base = np.asarray(base, dtype=float).copy()
    low = float(np.max(base))
    high = low + 40.0
    for _ in range(55):
        middle = (low + high) / 2.0
        candidate = base.copy()
        candidate[-1] = middle
        gap = np.max(candidate) - bootstrap_p95(candidate)
        if gap < target_gap:
            low = middle
        else:
            high = middle
    result = base.copy()
    result[-1] = (low + high) / 2.0
    return result


def test_fresh_generated_inputs_follow_audio_rules():
    """Exercise newly generated, neutrally named CSVs and derive every answer."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"

    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    cases = []

    # Passing data with varying row counts and distributions.
    for n in (19, 47, 83, 131):
        center = rng.uniform(70.0, 140.0)
        frame = make_frame(rng, n, rng.uniform(center - 2.0, center + 2.0, n))
        cases.append(frame)

    # Exact temperature sentinel and missing-status violations.
    for n in (31, 76, 119):
        frame = make_frame(rng, n, rng.uniform(90.0, 104.0, n))
        frame.loc[int(rng.integers(0, n)), "temperature"] = 999.9
        cases.append(frame)

        frame = make_frame(rng, n, rng.uniform(90.0, 104.0, n))
        frame.loc[int(rng.integers(0, n)), "status"] = np.nan
        cases.append(frame)

    # Clear pressure violations with randomized centers and row counts.
    for n in (29, 64, 107):
        center = rng.uniform(85.0, 125.0)
        pressure = rng.normal(center, 0.35, n)
        pressure[int(rng.integers(0, n))] = center + rng.uniform(22.0, 28.0)
        cases.append(make_frame(rng, n, pressure))

    # Cases on both sides of the strict ten-unit rule.
    for target_gap in (9.0, 11.0):
        n = 89
        center = rng.uniform(90.0, 115.0)
        pressure = pressure_with_gap(rng.normal(center, 0.3, n), target_gap)
        cases.append(make_frame(rng, n, pressure))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="dqcheck_") as directory:
        for index, frame in enumerate(cases):
            expected = expected_result(frame)
            written = frame.copy()
            if index % 3 == 0:
                written.columns = ["temperature ", "status ", "pressure "]

            path = os.path.join(directory, f"{uuid.uuid4().hex}.csv")
            written.to_csv(path, index=False)
            try:
                result = subprocess.run(
                    [sys.executable, SCRIPT_PATH, path],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"case {index}: timeout, expected {expected}")
                continue

            valid_stdout = result.stdout in (expected, expected + "\n")
            if result.returncode != 0 or not valid_stdout:
                failures.append(
                    f"case {index}: expected {expected}, return code {result.returncode}, "
                    f"stdout={result.stdout!r}"
                )

    if failures:
        pytest.fail("Generated-input failures: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
