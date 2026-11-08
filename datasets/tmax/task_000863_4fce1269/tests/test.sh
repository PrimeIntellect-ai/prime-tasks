#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import secrets
import subprocess
import tempfile
import pytest
import numpy as np
import pandas as pd


def run_detector(csv_path):
    cmd = ["python3", "/home/user/detector.py", "--input", csv_path]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {str(e)}"


def test_detector_script_exists():
    script_path = "/home/user/detector.py"
    assert os.path.exists(script_path), f"Detector script missing at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"


def test_adversarial_corpus_classification():
    evil_dir = "/app/holdout/evil/"
    clean_dir = "/app/holdout/clean/"

    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))

    assert len(evil_files) > 0, f"No evil files found in holdout corpus at {evil_dir}"
    assert len(clean_files) > 0, f"No clean files found in holdout corpus at {clean_dir}"

    evil_bypassed = []
    for f in evil_files:
        output = run_detector(f)
        if output != "EVIL":
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        output = run_detector(f)
        if output != "CLEAN":
            clean_modified.append(os.path.basename(f))

    total_evil = len(evil_files)
    total_clean = len(clean_files)

    err_msgs = []
    if evil_bypassed:
        err_msgs.append(f"{len(evil_bypassed)} of {total_evil} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        err_msgs.append(f"{len(clean_modified)} of {total_clean} clean modified: {', '.join(clean_modified)}")

    if err_msgs:
        pytest.fail(" | ".join(err_msgs))


def test_classification_on_opaque_runtime_corpus():
    # Build fresh cases under one neutrally named directory. Labels are kept only
    # in this process, and filenames do not reveal either class.
    seed = int.from_bytes(os.urandom(16), "big")
    rng = np.random.default_rng(seed)
    cases = ["CLEAN"] * 12 + ["EVIL"] * 12
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="telemetry_") as corpus_dir:
        generated = []
        for expected in cases:
            n = int(rng.integers(90, 141))
            speed = rng.normal(100.0, 20.0, n)

            if expected == "CLEAN":
                rpm = speed * rng.uniform(9.0, 11.0) + rng.normal(
                    0.0, rng.uniform(12.0, 30.0), n
                )
                # Missing values also occur in authentic logs, preventing a
                # detector from treating NaN presence as the class label.
                missing_fraction = float(rng.choice([0.03, 0.05]))
            else:
                rpm = speed * rng.uniform(1.5, 4.0) + rng.normal(
                    1000.0, rng.uniform(180.0, 260.0), n
                )
                # Some manipulated logs contain no missing values.
                missing_fraction = float(rng.choice([0.0, 0.08]))

            frame = pd.DataFrame({"Speed": speed, "RPM": rpm})
            count = int(n * missing_fraction)
            if count:
                speed_idx = rng.choice(n, count, replace=False)
                rpm_idx = rng.choice(n, count, replace=False)
                frame.loc[speed_idx, "Speed"] = np.nan
                frame.loc[rpm_idx, "RPM"] = np.nan

            path = os.path.join(corpus_dir, secrets.token_hex(12) + ".csv")
            frame.to_csv(path, index=False)
            generated.append((path, expected))

        rng.shuffle(generated)
        for path, expected in generated:
            output = run_detector(path)
            if output != expected:
                failures.append(
                    f"{os.path.basename(path)} expected {expected}, got {output!r}"
                )

    if failures:
        pytest.fail("Runtime corpus misclassified: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
