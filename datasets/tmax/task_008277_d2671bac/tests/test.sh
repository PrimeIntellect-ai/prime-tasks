#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.naive_bayes import GaussianNB

SCRIPT_PATH = "/home/user/analyze.py"
DATA_PATH = "/home/user/experiments.csv"
OUTPUT_PATH = "/home/user/ci.txt"


def test_analyze_script_exists():
    """Check if the analyze.py script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"Script file is missing at {SCRIPT_PATH}"


def test_run_analyze_script():
    """Execute the submitted artifact and require it to create fresh output."""
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}. stderr: {result.stderr}"
    )


def test_ci_output_exists():
    """Check if the ci.txt output file was created."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"


def test_ci_output_format_and_values():
    """Check if the ci.txt output file has the correct format and values."""
    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()

    # Check format: [lower, upper]
    match = re.match(r'^\[([0-9.]+),\s*([0-9.]+)\]$', content)
    assert match is not None, f"Output format in {OUTPUT_PATH} is incorrect. Expected format '[lower, upper]', got '{content}'"

    lower_str, upper_str = match.groups()

    # Check if they have 3 decimal places
    assert len(lower_str.split('.')[-1]) == 3, f"Lower bound should have exactly 3 decimal places, got {lower_str}"
    assert len(upper_str.split('.')[-1]) == 3, f"Upper bound should have exactly 3 decimal places, got {upper_str}"

    lower = float(lower_str)
    upper = float(upper_str)

    expected_lower = 0.787
    expected_upper = 0.913

    # Check values with a tolerance of 0.005
    assert abs(lower - expected_lower) <= 0.005, f"Lower bound {lower} is not within tolerance of expected {expected_lower}"
    assert abs(upper - expected_upper) <= 0.005, f"Upper bound {upper} is not within tolerance of expected {expected_upper}"


def test_script_computes_hidden_dataset_result():
    """Exercise the script on an unpredictable dataset and derive the oracle."""
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    seed = secrets.randbits(32)
    rng = np.random.default_rng(seed)
    n = 150
    y = np.repeat([0, 1], n // 2)
    rng.shuffle(y)
    probe = pd.DataFrame({
        "temperature": rng.normal(loc=0.75 * y, scale=1.0, size=n),
        "pressure": rng.normal(loc=-0.45 * y, scale=1.15, size=n),
        "humidity": rng.normal(loc=0.35 * y, scale=0.9, size=n),
        "outcome": y,
    })

    means = []
    for i in range(1000):
        sample = probe.sample(n=len(probe), replace=True, random_state=i)
        X = sample[["temperature", "pressure", "humidity"]]
        target = sample["outcome"]
        splitter = StratifiedKFold(n_splits=5, shuffle=True, random_state=i)
        scores = cross_val_score(
            GaussianNB(), X, target, cv=splitter, scoring="accuracy"
        )
        means.append(scores.mean())
    lower, upper = np.percentile(means, [2.5, 97.5])
    expected = f"[{lower:.3f}, {upper:.3f}]"

    try:
        probe.to_csv(DATA_PATH, index=False)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f"analyze.py failed on a hidden dataset with exit code "
            f"{result.returncode}. stderr: {result.stderr}"
        )
        assert os.path.isfile(OUTPUT_PATH), "analyze.py did not create ci.txt"
        with open(OUTPUT_PATH, "r") as f:
            actual = f.read().strip()
        assert actual == expected, (
            "ci.txt does not match the confidence interval obtained from the "
            "required 1000 bootstrap samples and stratified GaussianNB CV: "
            f"expected {expected}, got {actual}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
