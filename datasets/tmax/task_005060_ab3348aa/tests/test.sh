#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/classifier.py"


def run_classifier(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        timeout=30,
    ).returncode


def test_classifier_clean_corpus():
    """Test that the classifier accepts all clean files (exit code 0)."""
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"

    clean_dir = "/app/data/hidden_clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0): {failed_files}")


def test_classifier_evil_corpus():
    """Test that the classifier rejects all evil files (exit code 1)."""
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"

    evil_dir = "/app/data/hidden_evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed detection (exit code != 1): {failed_files}")


def make_baseline(rng, date):
    dates = pd.date_range(f"{date} 00:00:00", periods=1440, freq="min")
    x = np.linspace(0, 9, len(dates))
    df = pd.DataFrame({"timestamp": dates})
    for sensor in range(1, 11):
        phase = rng.uniform(-0.25, 0.25)
        noise = rng.normal(0, 0.025, len(dates))
        df[f"sensor{sensor}"] = 40 + 3 * np.sin(x + phase) + noise
    return df


def test_classifier_on_runtime_generated_neutral_paths():
    """Exercise content-derived cases whose paths reveal no expected class."""
    assert os.path.isfile(SCRIPT_PATH), f"Classifier script missing: {SCRIPT_PATH}"

    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    case_dir = tempfile.mkdtemp(prefix="dataset_", dir="/tmp")
    cases = []

    try:
        for batch in range(5):
            date = f"2024-{batch + 2:02d}-{batch + 3:02d}"
            baseline = make_baseline(rng, date)

            normal_path = os.path.join(case_dir, f"{secrets.token_hex(12)}.csv")
            baseline.to_csv(normal_path, index=False)
            cases.append((normal_path, 0))

            jumped = baseline.copy()
            jump_at = int(rng.integers(350, 900))
            sensor_columns = [f"sensor{i}" for i in range(1, 11)]
            jumped.loc[jump_at:, sensor_columns] *= 5.0
            jump_path = os.path.join(case_dir, f"{secrets.token_hex(12)}.csv")
            jumped.to_csv(jump_path, index=False)
            cases.append((jump_path, 1))

            duplicated = baseline.copy()
            maintenance_rows = np.arange(14 * 60, 16 * 60)
            chosen = rng.choice(maintenance_rows, size=10, replace=False)
            duplicated = pd.concat([duplicated, duplicated.iloc[chosen]], ignore_index=True)
            duplicated = duplicated.sort_values("timestamp", kind="stable")
            duplicate_path = os.path.join(case_dir, f"{secrets.token_hex(12)}.csv")
            duplicated.to_csv(duplicate_path, index=False)
            cases.append((duplicate_path, 1))

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for filepath, expected in cases:
            actual = run_classifier(filepath)
            if actual != expected:
                failures.append((os.path.basename(filepath), expected, actual))

        assert not failures, f"Runtime-generated cases were misclassified: {failures}"
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
