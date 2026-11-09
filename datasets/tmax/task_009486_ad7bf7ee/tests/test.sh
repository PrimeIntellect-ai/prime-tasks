#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import io
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD

SCRIPT_PATH = Path("/home/user/mlops_pipeline/build_features.py")
RAW_PATH = Path("/home/user/mlops_pipeline/raw_data.csv")
ARTIFACT_PATH = Path("/home/user/mlops_pipeline/artifacts/features.csv")


def expected_for(raw_bytes):
    df = pd.read_csv(io.BytesIO(raw_bytes))
    expected_author_ids = df["author_id"].fillna(-1).astype(int).astype(str).tolist()
    matrix = TfidfVectorizer().fit_transform(df["text"])
    coordinates = TruncatedSVD(n_components=2, random_state=42).fit_transform(matrix)
    return expected_author_ids, coordinates


def run_and_validate(raw_bytes):
    RAW_PATH.write_bytes(raw_bytes)
    if ARTIFACT_PATH.exists():
        ARTIFACT_PATH.unlink()

    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, "build_features.py failed:\n" + result.stdout + result.stderr
    assert ARTIFACT_PATH.is_file(), "Running build_features.py did not generate features.csv."

    with ARTIFACT_PATH.open("r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fieldnames = reader.fieldnames or []

    expected_ids, expected_coordinates = expected_for(raw_bytes)
    assert len(rows) == len(expected_ids), "features.csv has the wrong number of rows."
    assert "svd_0" in fieldnames and "svd_1" in fieldnames, "SVD columns are missing."
    assert [row["author_id"] for row in rows] == expected_ids, \
        "author_id was not imputed with -1 and serialized as standard integers."

    try:
        actual_coordinates = np.asarray(
            [[float(row["svd_0"]), float(row["svd_1"])] for row in rows],
            dtype=float,
        )
    except (TypeError, ValueError) as exc:
        raise AssertionError("SVD coordinates must be valid floats.") from exc

    assert np.isfinite(actual_coordinates).all(), "SVD coordinates must be finite."
    assert np.allclose(actual_coordinates, expected_coordinates, rtol=1e-7, atol=1e-9), \
        "SVD coordinates do not match TF-IDF followed by TruncatedSVD(n_components=2, random_state=42)."


def test_pipeline_execution_coordinates_and_reproducibility():
    assert SCRIPT_PATH.is_file(), "build_features.py is missing."
    original_raw = RAW_PATH.read_bytes()
    alternate_raw = b"""doc_id,text,author_id
101,alpha beta gamma,7
102,beta delta,
103,gamma epsilon,0
104,zeta eta theta,
105,alpha theta iota,-5
106,kappa lambda delta,99
"""

    try:
        run_and_validate(original_raw)
        first_artifact = ARTIFACT_PATH.read_bytes()
        run_and_validate(original_raw)
        second_artifact = ARTIFACT_PATH.read_bytes()
        assert first_artifact == second_artifact, \
            "Running the pipeline twice on identical input did not produce an identical artifact."

        # Exercise the script on independently checked input so fixed, fabricated CSV
        # contents cannot satisfy the verifier.
        run_and_validate(alternate_raw)
    finally:
        RAW_PATH.write_bytes(original_raw)
        if ARTIFACT_PATH.exists():
            ARTIFACT_PATH.unlink()
        subprocess.run(
            ["python3", str(SCRIPT_PATH)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
            check=False,
        )


def test_features_csv_exists():
    assert os.path.isfile("/home/user/mlops_pipeline/artifacts/features.csv"), "features.csv was not generated."


def test_author_id_imputation_and_type():
    csv_path = "/home/user/mlops_pipeline/artifacts/features.csv"
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 7, "Expected 7 rows in features.csv."

    expected_author_ids = ['10', '-1', '20', '-1', '30', '-1', '40']
    actual_author_ids = [row['author_id'] for row in rows]

    for i, (actual, expected) in enumerate(zip(actual_author_ids, expected_author_ids)):
        assert actual == expected, f"Row {i+1}: expected author_id '{expected}', got '{actual}'. Ensure missing values are imputed with -1 and the column is cast to integer."


def test_svd_columns_exist():
    csv_path = "/home/user/mlops_pipeline/artifacts/features.csv"
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames

    assert "svd_0" in fieldnames, "Column 'svd_0' is missing from features.csv."
    assert "svd_1" in fieldnames, "Column 'svd_1' is missing from features.csv."

    # Check that they are floats
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            try:
                float(row["svd_0"])
                float(row["svd_1"])
            except ValueError:
                assert False, f"Row {i+1}: svd_0 and svd_1 must be valid floats."


def test_build_features_script_fixed():
    script_path = "/home/user/mlops_pipeline/build_features.py"
    with open(script_path, "r") as f:
        content = f.read()

    # Check for random_state=42
    assert re.search(r"random_state\s*=\s*42", content), "TruncatedSVD is not initialized with random_state=42 in build_features.py."

    # Check for imputation logic
    assert "-1" in content, "Missing value imputation with -1 not found in build_features.py."
    assert "int" in content.lower(), "Integer casting logic not found in build_features.py."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
