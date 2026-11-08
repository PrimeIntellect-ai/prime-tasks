#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import subprocess
import tempfile

import requests
import pytest
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from scipy.stats import pearsonr

URL = "http://127.0.0.1:8000/api/analyze"
EXPECTED_KEYS = {"correlation_f3_score", "pc1_mean_ci_lower", "pc1_mean_ci_upper"}


def calculate_expected(csv_content):
    df = pd.read_csv(io.StringIO(csv_content))
    assert list(df.columns) == ["f1", "f2", "f3", "f4", "f5"]

    for col in df.columns:
        median_val = df[col].median(skipna=True)
        median_rounded = np.round(median_val)
        df[col] = df[col].fillna(median_rounded).astype("int64")

    cleaned_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as cleaned:
            cleaned_path = cleaned.name
            df.to_csv(cleaned, index=False, header=False)
        result = subprocess.run(
            ["/app/prop_scorer", cleaned_path],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        if cleaned_path and os.path.exists(cleaned_path):
            os.unlink(cleaned_path)

    scores = np.array([float(line) for line in result.stdout.splitlines() if line.strip()])
    assert len(scores) == len(df), "Oracle did not return one score per cleaned row"

    correlation_f3_score, _ = pearsonr(df["f3"], scores)
    scaled_data = StandardScaler().fit_transform(df)
    pc1 = PCA(n_components=1).fit_transform(scaled_data).flatten()

    n = len(pc1)
    mean_pc1 = np.mean(pc1)
    std_pc1 = np.std(pc1, ddof=1)
    margin_of_error = 1.96 * (std_pc1 / np.sqrt(n))
    values = (correlation_f3_score, mean_pc1 - margin_of_error, mean_pc1 + margin_of_error)
    assert np.all(np.isfinite(values))
    return values


def make_random_csv():
    rng = secrets.SystemRandom()
    while True:
        rows = 12
        matrix = [[rng.randint(-150, 250) for _ in range(5)] for _ in range(rows)]

        # Every column contains missing values, while retaining enough observations
        # for median imputation, scaling, PCA, and correlation.
        missing = set()
        for col in range(5):
            for row in rng.sample(range(rows), 2):
                missing.add((row, col))

        lines = ["f1,f2,f3,f4,f5"]
        for row in range(rows):
            fields = ["" if (row, col) in missing else str(matrix[row][col]) for col in range(5)]
            lines.append(",".join(fields))
        csv_content = "\n".join(lines) + "\n"

        try:
            calculate_expected(csv_content)
            return csv_content
        except (AssertionError, ValueError):
            continue


def check_payload(csv_content, filename):
    expected_correlation, expected_lower, expected_upper = calculate_expected(csv_content)
    files = {"file": (filename, csv_content, "text/csv")}

    try:
        response = requests.post(URL, files=files, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {URL}. Error: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    actual_keys = set(data.keys())
    assert EXPECTED_KEYS.issubset(actual_keys), (
        f"Missing keys in response. Expected {EXPECTED_KEYS}, got {actual_keys}"
    )

    tolerance = 0.001
    assert abs(data["correlation_f3_score"] - expected_correlation) <= tolerance, (
        f"correlation_f3_score mismatch. Expected ~{expected_correlation:.4f}, "
        f"got {data['correlation_f3_score']}"
    )
    assert abs(data["pc1_mean_ci_lower"] - expected_lower) <= tolerance, (
        f"pc1_mean_ci_lower mismatch. Expected ~{expected_lower:.4f}, "
        f"got {data['pc1_mean_ci_lower']}"
    )
    assert abs(data["pc1_mean_ci_upper"] - expected_upper) <= tolerance, (
        f"pc1_mean_ci_upper mismatch. Expected ~{expected_upper:.4f}, "
        f"got {data['pc1_mean_ci_upper']}"
    )


def test_api_analyze_endpoint():
    fixed_csv = """f1,f2,f3,f4,f5
10,,30,40,50
20,25,,45,55
30,35,40,,60
40,45,50,55,
,,60,65,70
"""
    check_payload(fixed_csv, "fixed.csv")

    # Runtime-generated payloads prevent a service from passing by returning the
    # three constants associated with the public fixture.
    for index in range(3):
        check_payload(make_random_csv(), f"random-{index}.csv")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
