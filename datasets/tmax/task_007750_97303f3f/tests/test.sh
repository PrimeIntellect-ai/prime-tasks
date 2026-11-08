#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import stat
import subprocess
import pandas as pd
import pytest


def test_run_sh_exists_and_executable():
    """Check that run.sh exists and is executable."""
    run_sh_path = "/home/user/pipeline/run.sh"
    assert os.path.isfile(run_sh_path), f"{run_sh_path} does not exist."
    st = os.stat(run_sh_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{run_sh_path} is not executable."


def test_prepare_py_exists():
    """Check that prepare.py exists."""
    prepare_py_path = "/home/user/pipeline/prepare.py"
    assert os.path.isfile(prepare_py_path), f"{prepare_py_path} does not exist."


def test_run_pipeline():
    """Execute the submitted pipeline rather than trusting pre-created outputs."""
    result = subprocess.run(
        ["/home/user/pipeline/run.sh"],
        cwd="/home/user/pipeline",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert result.returncode == 0, f"run.sh failed with output:\n{result.stdout}"


def test_parquet_file_exists():
    """Check that the output parquet file exists and is not empty."""
    parquet_path = "/home/user/data/prepared.parquet"
    assert os.path.isfile(parquet_path), f"{parquet_path} does not exist."
    assert os.path.getsize(parquet_path) > 0, f"{parquet_path} is empty."


def test_parquet_contents():
    """Open the Parquet file and validate its complete schema and contents."""
    parquet_path = "/home/user/data/prepared.parquet"
    try:
        actual = pd.read_parquet(parquet_path)
    except Exception as exc:
        pytest.fail(f"{parquet_path} is not a readable Parquet file: {exc}")

    frames = []
    for i in range(1, 4):
        csv_path = f"/home/user/data/data_{i}.csv"
        assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
        frames.append(pd.read_csv(csv_path))

    expected = pd.concat(frames, ignore_index=True)
    expected = expected.sort_values("id", ascending=True).reset_index(drop=True)
    expected["cov_AB"] = expected["sensor_A"].rolling(window=10).cov(expected["sensor_B"])
    expected["cov_AC"] = expected["sensor_A"].rolling(window=10).cov(expected["sensor_C"])
    expected = expected[expected["cov_AB"] >= 0].dropna()

    expected_columns = ["id", "sensor_A", "sensor_B", "sensor_C", "cov_AB", "cov_AC"]
    assert list(actual.columns) == expected_columns, (
        f"Parquet schema mismatch. Expected columns {expected_columns}, "
        f"got {list(actual.columns)}."
    )
    assert len(actual) == len(expected), (
        f"Parquet row count mismatch. Expected {len(expected)}, got {len(actual)}."
    )
    assert actual["id"].is_monotonic_increasing, "Parquet rows are not sorted by id."
    assert not actual.isna().any().any(), "Parquet output contains NaN values."
    assert (actual["cov_AB"] >= 0).all(), "Parquet output contains negative cov_AB values."

    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected[expected_columns].reset_index(drop=True),
        check_dtype=False,
        check_exact=False,
        rtol=1e-10,
        atol=1e-12,
    )


def test_correlation_value():
    """Verify that the computed correlation value is correct."""
    corr_txt_path = "/home/user/pipeline/correlation.txt"
    assert os.path.isfile(corr_txt_path), f"{corr_txt_path} does not exist."

    # Read and parse the original CSVs to compute the expected truth
    data = []
    for i in range(1, 4):
        csv_path = f'/home/user/data/data_{i}.csv'
        assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                data.append({
                    'id': int(row['id']),
                    'A': float(row['sensor_A']),
                    'B': float(row['sensor_B']),
                    'C': float(row['sensor_C'])
                })

    # Sort by id
    data.sort(key=lambda x: x['id'])

    cov_AB_list = []
    cov_AC_list = []

    # Compute rolling covariance (window=10)
    for i in range(len(data)):
        if i < 9:
            cov_AB_list.append(None)
            cov_AC_list.append(None)
        else:
            window = data[i-9:i+1]
            mean_A = sum(d['A'] for d in window) / 10
            mean_B = sum(d['B'] for d in window) / 10
            mean_C = sum(d['C'] for d in window) / 10

            # Sample covariance (divide by n-1 = 9)
            cov_AB = sum((d['A'] - mean_A) * (d['B'] - mean_B) for d in window) / 9
            cov_AC = sum((d['A'] - mean_A) * (d['C'] - mean_C) for d in window) / 9

            cov_AB_list.append(cov_AB)
            cov_AC_list.append(cov_AC)

    filtered_AB = []
    filtered_AC = []

    # Filter out NaNs and negative cov_AB
    for ab, ac in zip(cov_AB_list, cov_AC_list):
        if ab is not None and ab >= 0:
            filtered_AB.append(ab)
            filtered_AC.append(ac)

    # Compute Pearson correlation
    n = len(filtered_AB)
    assert n > 0, "No data left after filtering, cannot compute correlation."

    mean_AB = sum(filtered_AB) / n
    mean_AC = sum(filtered_AC) / n

    cov_AB_AC = sum((ab - mean_AB) * (ac - mean_AC) for ab, ac in zip(filtered_AB, filtered_AC))
    var_AB = sum((ab - mean_AB) ** 2 for ab in filtered_AB)
    var_AC = sum((ac - mean_AC) ** 2 for ac in filtered_AC)

    corr = cov_AB_AC / math.sqrt(var_AB * var_AC)
    expected_corr_str = f"{corr:.4f}"

    # Read actual correlation
    with open(corr_txt_path, 'r', encoding='utf-8') as f:
        actual_corr_str = f.read().strip()

    assert actual_corr_str == expected_corr_str, (
        f"Correlation mismatch. Expected {expected_corr_str}, got {actual_corr_str}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
