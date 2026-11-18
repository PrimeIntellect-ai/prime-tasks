#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import stat
import subprocess

import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score

RAW_PATH = "/home/user/data_raw.csv"
PREPROCESS_PATH = "/home/user/preprocess.py"
TRAIN_PATH = "/home/user/train.py"
CLEAN_PATH = "/home/user/data_clean.csv"
SCORE_PATH = "/home/user/best_score.txt"

EXPECTED_RAW = """f1,f2,group,target
0.5,0.1,A,1
0.2,0.9,B,0
0.1,0.2,C,1
0.6,0.2,A,1
0.3,0.8,B,0
0.1,0.1,C,0
0.9,0.5,A,1
0.8,0.4,B,1
0.2,0.3,C,0
0.4,0.5,A,1
"""

EXPECTED_TRAIN = """import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score
import json

def main():
    df = pd.read_csv('/home/user/data_clean.csv')

    # Validation check
    if df['group_id'].dtype != 'int64':
        raise TypeError(f"group_id must be strictly int64, got {df['group_id'].dtype}")

    X = df[['f1', 'f2', 'group_id']]
    y = df['target']

    clf = RandomForestClassifier(random_state=42, n_estimators=10)
    score = cross_val_score(clf, X, y, cv=2).mean()

    with open('/home/user/best_score.txt', 'w') as f:
        f.write(str(score))

if __name__ == "__main__":
    main()
"""


def assert_regular_file(path):
    assert os.path.isfile(path), f"Required file missing at {path}."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} must be a regular file."


def assert_protected_files_unchanged():
    assert_regular_file(RAW_PATH)
    assert_regular_file(TRAIN_PATH)
    with open(RAW_PATH, "r") as f:
        assert f.read() == EXPECTED_RAW, "data_raw.csv was modified."
    with open(TRAIN_PATH, "r") as f:
        assert f.read() == EXPECTED_TRAIN, "train.py was modified."


def expected_clean_dataframe():
    raw = pd.read_csv(RAW_PATH)
    expected = raw.drop(columns=["group"]).copy()
    expected["group_id"] = raw["group"].map({"A": 1, "B": 2}).fillna(-1).astype("int64")
    return expected


def assert_clean_matches_raw():
    assert_regular_file(CLEAN_PATH)
    actual = pd.read_csv(CLEAN_PATH)
    expected = expected_clean_dataframe()
    pd.testing.assert_frame_equal(actual, expected, check_dtype=True, check_like=False)
    assert actual["group_id"].dtype == "int64"


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    assert_regular_file(PREPROCESS_PATH)
    assert_protected_files_unchanged()

    for artifact in (CLEAN_PATH, SCORE_PATH):
        if os.path.lexists(artifact):
            os.remove(artifact)

    subprocess.run(
        ["python3", PREPROCESS_PATH],
        check=True,
        timeout=60,
        cwd="/home/user",
    )
    assert_protected_files_unchanged()
    assert_clean_matches_raw()

    subprocess.run(
        ["python3", TRAIN_PATH],
        check=True,
        timeout=120,
        cwd="/home/user",
    )
    assert_protected_files_unchanged()
    assert_clean_matches_raw()


def test_best_score_exists_and_valid():
    score_path = "/home/user/best_score.txt"
    assert os.path.isfile(score_path), f"Score artifact missing at {score_path}."

    with open(score_path, 'r') as f:
        content = f.read().strip()

    try:
        score = float(content)
    except ValueError:
        pytest.fail(f"Content of {score_path} is not a valid float: {content}")

    assert math.isfinite(score), "Score must be finite."

    expected = expected_clean_dataframe()
    X = expected[["f1", "f2", "group_id"]]
    y = expected["target"]
    clf = RandomForestClassifier(random_state=42, n_estimators=10)
    expected_score = cross_val_score(clf, X, y, cv=2).mean()
    assert score == pytest.approx(expected_score, abs=1e-12, rel=0), (
        f"Incorrect score: expected {expected_score}, got {score}."
    )


def test_data_clean_csv():
    clean_path = "/home/user/data_clean.csv"
    assert os.path.isfile(clean_path), f"Clean data artifact missing at {clean_path}."

    with open(clean_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) > 0, "data_clean.csv is empty."
    assert 'group_id' in rows[0], "group_id column missing from data_clean.csv."

    group_ids = [row['group_id'] for row in rows]

    # Check that -1 is in the group_ids
    assert '-1' in group_ids, "Missing values were not filled with -1 in group_id column."

    # Check that all group_ids are formatted as integers (no decimals)
    for gid in group_ids:
        try:
            val = int(gid)
            # Ensure it's strictly formatted as an integer, not a float string like "1.0"
            assert str(val) == gid, f"group_id value '{gid}' is not strictly formatted as an integer."
        except ValueError:
            pytest.fail(f"group_id value '{gid}' is not a valid integer.")

    assert_clean_matches_raw()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
