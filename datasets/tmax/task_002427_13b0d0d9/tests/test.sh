#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

import numpy as np
import pandas as pd
import pytest

CLEAN_PATH = "/home/user/data/clean.csv"
RAW_PATH = "/home/user/data/raw.csv"
EVALUATOR_PATH = "/app/evaluator"


def test_clean_csv_exists():
    assert os.path.exists(CLEAN_PATH), f"Clean dataset missing at {CLEAN_PATH}"
    assert os.path.isfile(CLEAN_PATH), f"{CLEAN_PATH} is not a file"
    assert os.path.getsize(CLEAN_PATH) > 0, f"{CLEAN_PATH} is empty"


def _count_matches_with_multiplicity(values, reference):
    values = np.sort(np.asarray(values, dtype=float))
    reference = np.sort(np.asarray(reference, dtype=float))
    i = j = matches = 0
    while i < len(values) and j < len(reference):
        tolerance = 1e-6 * max(1.0, abs(reference[j]))
        difference = values[i] - reference[j]
        if abs(difference) <= tolerance:
            matches += 1
            i += 1
            j += 1
        elif difference < -tolerance:
            i += 1
        else:
            j += 1
    return matches


def test_clean_csv_uses_the_supplied_dataset():
    assert os.path.isfile(RAW_PATH), f"Raw dataset missing at {RAW_PATH}"

    clean = pd.read_csv(CLEAN_PATH)
    raw = pd.read_csv(RAW_PATH)

    assert "target" in clean.columns, "Clean dataset does not contain target"
    assert "target" in raw.columns, "Raw dataset does not contain target"
    assert len(clean) >= 300, (
        f"Clean dataset has only {len(clean)} rows; it is not a substantive cleaning "
        "of the 1000-row source dataset"
    )

    clean_targets = pd.to_numeric(clean["target"], errors="coerce").to_numpy(dtype=float)
    assert np.isfinite(clean_targets).all(), "Clean target contains missing or non-finite values"

    # Reconstruct the pristine target values independently so replacing raw.csv cannot
    # make fabricated targets appear to have come from the supplied source dataset.
    pristine_targets = np.random.RandomState(42).standard_normal(1000)

    raw_targets = pd.to_numeric(raw["target"], errors="coerce").to_numpy(dtype=float)
    raw_targets = raw_targets[np.isfinite(raw_targets) & (raw_targets != 9999.0)]
    raw_matches = _count_matches_with_multiplicity(raw_targets, pristine_targets)
    assert raw_matches >= 900, "The supplied raw dataset was replaced or materially altered"

    matches = _count_matches_with_multiplicity(clean_targets, pristine_targets)
    required_matches = max(250, int(np.ceil(0.85 * len(clean_targets))))
    assert matches >= required_matches, (
        f"Only {matches} of {len(clean_targets)} clean target values can be traced to "
        f"raw.csv; at least {required_matches} are required"
    )


def test_evaluator_score():
    assert os.path.exists(CLEAN_PATH), f"Clean dataset missing at {CLEAN_PATH}"
    assert os.path.exists(EVALUATOR_PATH), f"Evaluator missing at {EVALUATOR_PATH}"

    result = subprocess.run(
        [EVALUATOR_PATH, CLEAN_PATH],
        capture_output=True,
        text=True,
        check=False
    )

    assert result.returncode == 0, f"Evaluator failed with return code {result.returncode}. stderr: {result.stderr}"

    output = result.stdout.strip()
    try:
        score = float(output)
    except ValueError:
        pytest.fail(f"Evaluator output could not be parsed as float. Output: {output}")

    assert score >= 0.35, f"Evaluator score {score} is below the threshold of 0.35"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
