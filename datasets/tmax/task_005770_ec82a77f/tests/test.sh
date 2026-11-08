#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
from pandas.testing import assert_frame_equal
from scipy import stats

RUN_SCRIPT = "/home/user/run.sh"
RAW_PATH = "/home/user/raw_data.csv"
TRAINING_PATH = "/home/user/training_data.csv"
STATS_PATH = "/home/user/stats.json"
COLUMNS = [
    "user_id",
    "session_duration_sec",
    "clicks",
    "converted",
    "clicks_per_minute",
]


def pristine_raw_data():
    # Independently recreate the immutable input supplied by setup, including
    # its CSV serialization round trip.
    np.random.seed(10)
    n = 2000
    df = pd.DataFrame({
        "user_id": ["U" + str(i).zfill(4) for i in range(n)],
        "session_duration_sec": np.random.normal(120, 40, n),
        "clicks": np.random.poisson(5, n),
        "converted": np.random.choice([0, 1], n, p=[0.8, 0.2]),
    })
    df.loc[10:20, "session_duration_sec"] = -5
    df.loc[30:40, "clicks"] = -1
    df.loc[50:60, "user_id"] = np.nan
    df.loc[df["converted"] == 1, "clicks"] += 3

    buf = io.StringIO()
    df.to_csv(buf, index=False)
    return pd.read_csv(io.StringIO(buf.getvalue()))


def expected_for_seed(seed):
    df = pristine_raw_data()
    df = df[df["user_id"].notna()]
    df = df[df["user_id"].astype(str).str.strip() != ""]
    df = df[df["session_duration_sec"] > 0]
    df = df[df["clicks"] >= 0].copy()
    df["clicks_per_minute"] = df["clicks"] / (df["session_duration_sec"] / 60)

    c0 = df[df["converted"] == 0].sample(n=500, replace=True, random_state=seed)
    c1 = df[df["converted"] == 1].sample(n=500, replace=True, random_state=seed)
    balanced = pd.concat([c0, c1], ignore_index=True)[COLUMNS]
    t_stat, p_value = stats.ttest_ind(
        c1["clicks_per_minute"],
        c0["clicks_per_minute"],
        equal_var=True,
    )
    return balanced, float(t_stat), float(p_value)


def run_and_validate(seed):
    result = subprocess.run(
        [RUN_SCRIPT, str(seed)], capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"run.sh failed for seed {seed} with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    assert os.path.exists(TRAINING_PATH), f"Output file {TRAINING_PATH} was not created."
    assert os.path.exists(STATS_PATH), f"Output file {STATS_PATH} was not created."

    actual = pd.read_csv(TRAINING_PATH)
    assert list(actual.columns) == COLUMNS, (
        f"Columns in training_data.csv do not match expected. Got {list(actual.columns)}"
    )
    assert len(actual) == 1000, (
        f"Expected exactly 1000 rows in training_data.csv, got {len(actual)}"
    )
    assert actual["converted"].value_counts().to_dict() == {0: 500, 1: 500}, (
        "training_data.csv must contain exactly 500 rows from each converted group"
    )

    expected, expected_t, expected_p = expected_for_seed(seed)

    # Combination order is unspecified, so compare the complete sampled row
    # multisets after deterministic sorting. This checks filtering, sampling
    # multiplicities, source values, labels, and the engineered feature.
    sort_columns = COLUMNS
    actual_sorted = actual.sort_values(sort_columns, kind="mergesort").reset_index(drop=True)
    expected_sorted = expected.sort_values(sort_columns, kind="mergesort").reset_index(drop=True)
    assert_frame_equal(
        actual_sorted,
        expected_sorted,
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )

    with open(STATS_PATH, "r") as f:
        student_stats = json.load(f)
    assert set(student_stats) == {"t_statistic", "p_value"}, (
        "stats.json must contain exactly 't_statistic' and 'p_value'"
    )
    assert isinstance(student_stats["t_statistic"], (int, float))
    assert isinstance(student_stats["p_value"], (int, float))
    assert math.isfinite(student_stats["t_statistic"])
    assert math.isfinite(student_stats["p_value"])

    # Preserve the original golden-statistics assertions.
    assert abs(student_stats["t_statistic"] - expected_t) < 1e-4, (
        f"t_statistic mismatch. Expected approx {expected_t}, "
        f"got {student_stats['t_statistic']}"
    )
    assert abs(student_stats["p_value"] - expected_p) < 1e-4, (
        f"p_value mismatch. Expected approx {expected_p}, got {student_stats['p_value']}"
    )

    # Also ensure the reported statistics are computed from the emitted CSV.
    out_c1 = actual[actual["converted"] == 1]["clicks_per_minute"]
    out_c0 = actual[actual["converted"] == 0]["clicks_per_minute"]
    output_t, output_p = stats.ttest_ind(out_c1, out_c0, equal_var=True)
    assert abs(student_stats["t_statistic"] - output_t) < 1e-10
    assert abs(student_stats["p_value"] - output_p) < 1e-10


def test_pipeline_outputs_and_reproducibility():
    assert os.path.exists(RUN_SCRIPT), f"Expected script {RUN_SCRIPT} does not exist."
    assert os.access(RUN_SCRIPT, os.X_OK), f"Script {RUN_SCRIPT} is not executable."

    # Derive all expectations from a pristine reconstruction rather than from
    # an agent-modifiable raw_data.csv.
    assert_frame_equal(
        pd.read_csv(RAW_PATH),
        pristine_raw_data(),
        check_dtype=True,
        check_exact=True,
    )

    run_and_validate(123)
    first_csv = open(TRAINING_PATH, "rb").read()
    first_stats = open(STATS_PATH, "rb").read()

    # Exercise a second seed so a hard-coded seed-123 result cannot pass.
    run_and_validate(9876)

    # Re-running the original seed must reproduce byte-identical outputs.
    run_and_validate(123)
    assert open(TRAINING_PATH, "rb").read() == first_csv, (
        "training_data.csv is not reproducible for the same seed"
    )
    assert open(STATS_PATH, "rb").read() == first_stats, (
        "stats.json is not reproducible for the same seed"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
