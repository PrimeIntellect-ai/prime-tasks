#!/bin/bash
set -e
mkdir -p /logs/verifier

PIPELINE_DIR=/home/user/pipeline

# Exercise the requested entry point from a clean output state.
rm -f "$PIPELINE_DIR/processed.csv" "$PIPELINE_DIR/correlation.txt" "$PIPELINE_DIR/mse.txt"
if ! timeout 30s bash "$PIPELINE_DIR/run_pipeline.sh" >/tmp/run_pipeline.stdout 2>/tmp/run_pipeline.stderr; then
    cat /tmp/run_pipeline.stdout /tmp/run_pipeline.stderr
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import pandas as pd
import pytest

PIPELINE_DIR = "/home/user/pipeline"


def read_numeric_file(name):
    path = os.path.join(PIPELINE_DIR, name)
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        val = f.read().strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", val), \
        f"{name} must contain only one numeric value, got: {val!r}"
    return val, float(val)


def test_mse_txt():
    mse_path = os.path.join(PIPELINE_DIR, "mse.txt")
    assert os.path.isfile(mse_path), f"File {mse_path} does not exist."
    with open(mse_path, "r") as f:
        val = f.read().strip()
    try:
        mse_val = float(val)
    except ValueError:
        pytest.fail(f"mse.txt does not contain a valid float: {val}")

    assert mse_val == 0.0, f"Expected MSE to be 0.0, but got {mse_val}"


def test_correlation_txt():
    corr_path = os.path.join(PIPELINE_DIR, "correlation.txt")
    assert os.path.isfile(corr_path), f"File {corr_path} does not exist."
    with open(corr_path, "r") as f:
        val = f.read().strip()
    try:
        corr_val = float(val)
    except ValueError:
        pytest.fail(f"correlation.txt does not contain a valid float: {val}")

    assert corr_val == 0.0076, f"Expected correlation to be exactly 0.0076, but got {corr_val}"
    assert re.fullmatch(r"[+-]?\d+\.\d{4}", val), \
        "correlation.txt must contain only a numeric value with four decimal places"


def test_run_pipeline_sh():
    sh_path = os.path.join(PIPELINE_DIR, "run_pipeline.sh")
    assert os.path.isfile(sh_path), f"File {sh_path} does not exist."

    with open(sh_path, "r") as f:
        content = f.read()

    assert "etl.py" in content, "run_pipeline.sh does not appear to run etl.py"
    assert "analysis.py" in content, "run_pipeline.sh does not appear to run analysis.py"
    assert "score.py" in content, "run_pipeline.sh does not appear to run score.py"
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "analysis.py")), "analysis.py does not exist"


def test_processed_csv_precision():
    csv_path = os.path.join(PIPELINE_DIR, "processed.csv")
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip().split(',') for line in f.readlines() if line.strip()]

    assert len(lines) >= 5, "processed.csv does not contain the expected number of rows."

    try:
        user_id_idx = lines[0].index("user_id")
        feature_2_idx = lines[0].index("feature_2")
    except ValueError:
        pytest.fail("processed.csv is missing 'user_id' or 'feature_2' in the header.")

    expected_f2 = {
        "1": "9007199254740993",
        "2": "0",
        "3": "9007199254740995",
        "4": "0"
    }

    for row in lines[1:]:
        uid = row[user_id_idx]
        f2_str = row[feature_2_idx]
        if uid in expected_f2:
            expected_val = expected_f2[uid]
            assert f2_str == expected_val or f2_str == f"{expected_val}.0", \
                f"Precision lost or incorrect value for user {uid}. Expected {expected_val}, got {f2_str}"

    # Close the original unknown-user loophole by requiring exactly the joined input users.
    assert [row[user_id_idx] for row in lines[1:]] == ["1", "2", "3", "4"]
    assert {row[user_id_idx]: row[feature_2_idx] for row in lines[1:]} == expected_f2


def test_etl_uses_nullable_integer_mechanism():
    etl_path = os.path.join(PIPELINE_DIR, "etl.py")
    assert os.path.isfile(etl_path)
    source = open(etl_path, encoding="utf-8").read()
    assert re.search(r"Int64|Int64Dtype|convert_dtypes", source), \
        "etl.py must use a pandas nullable integer dtype for feature_2"


def test_pipeline_on_derived_unseen_inputs():
    paths = ["data_A.csv", "data_B.csv", "labels.csv"]
    originals = {
        name: open(os.path.join(PIPELINE_DIR, name), "rb").read()
        for name in paths
    }

    data_a = """user_id,feature_1
11,1.25
12,2.5
13,4.75
14,8.0
15,16.5
"""
    data_b = """user_id,feature_2
11,9007199254740993
13,9007199254740997
15,9007199254741001
"""
    labels = """user_id,label
11,0
12,3
13,5
14,9
15,17
"""

    try:
        for name, content in (("data_A.csv", data_a), ("data_B.csv", data_b), ("labels.csv", labels)):
            with open(os.path.join(PIPELINE_DIR, name), "w", encoding="utf-8") as f:
                f.write(content)

        for name in ("processed.csv", "correlation.txt", "mse.txt"):
            path = os.path.join(PIPELINE_DIR, name)
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            ["bash", "run_pipeline.sh"], cwd=PIPELINE_DIR,
            text=True, capture_output=True, timeout=30
        )
        assert result.returncode == 0, result.stdout + result.stderr

        for name in ("processed.csv", "correlation.txt", "mse.txt"):
            assert os.path.isfile(os.path.join(PIPELINE_DIR, name)), \
                f"run_pipeline.sh did not generate {name}"

        with open(os.path.join(PIPELINE_DIR, "processed.csv"), newline="") as f:
            rows = list(csv.DictReader(f))
        expected_f2 = {
            "11": "9007199254740993",
            "12": "0",
            "13": "9007199254740997",
            "14": "0",
            "15": "9007199254741001",
        }
        assert [r["user_id"] for r in rows] == list(expected_f2)
        assert {r["user_id"]: r["feature_2"] for r in rows} == expected_f2

        # Derive both answers independently from the temporary source inputs.
        expected = pd.DataFrame({
            "user_id": [11, 12, 13, 14, 15],
            "feature_1": [1.25, 2.5, 4.75, 8.0, 16.5],
            "feature_2": [9007199254740993, 0, 9007199254740997, 0, 9007199254741001],
        })
        expected_corr_text = f"{expected['feature_1'].corr(expected['feature_2']):.4f}"
        corr_text, corr_value = read_numeric_file("correlation.txt")
        assert corr_text == expected_corr_text, \
            f"Expected derived correlation {expected_corr_text}, got {corr_text}"

        expected_labels = pd.read_csv(os.path.join(PIPELINE_DIR, "labels.csv"))
        scored = expected.merge(expected_labels, on="user_id")
        prediction = scored["feature_1"] + scored["feature_2"]
        expected_mse = float(((prediction - scored["label"]) ** 2).mean())
        mse_text, mse_value = read_numeric_file("mse.txt")
        assert math.isfinite(mse_value)
        assert math.isclose(mse_value, expected_mse, rel_tol=1e-12, abs_tol=1e-12), \
            f"Expected derived MSE {expected_mse}, got {mse_value}"

        score = subprocess.run(
            ["python3", "score.py"], cwd=PIPELINE_DIR,
            text=True, capture_output=True, timeout=15, check=True
        )
        assert score.stdout.strip() == mse_text, \
            "mse.txt must contain the value printed by score.py"
    finally:
        for name, content in originals.items():
            with open(os.path.join(PIPELINE_DIR, name), "wb") as f:
                f.write(content)
        # Leave the requested final artifacts corresponding to the original inputs.
        subprocess.run(["bash", "run_pipeline.sh"], cwd=PIPELINE_DIR,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=30, check=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
