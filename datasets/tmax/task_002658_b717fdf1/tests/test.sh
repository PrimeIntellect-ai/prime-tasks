#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import itertools
import pytest
import pandas as pd

REPORT_PATH = "/home/user/test_report.json"
RUN1_PATH = "/home/user/run1_output.csv"
RUN2_PATH = "/home/user/run2_output.csv"
SCRIPT_PATH = "/home/user/evaluate_reproducibility.py"

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected file {SCRIPT_PATH} to exist."
    assert not os.path.islink(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a regular file, not a symlink."

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Expected file {REPORT_PATH} to exist."

def test_report_schema():
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    expected_keys = {"max_abs_diff", "is_reproducible", "highest_cov_pair", "highest_cov_value"}
    assert set(report.keys()) == expected_keys, f"Report keys do not match expected schema. Got {list(report.keys())}"

def test_report_values():
    with open(REPORT_PATH, 'r') as f:
        report = json.load(f)

    # Check types
    assert isinstance(report["max_abs_diff"], float), "max_abs_diff must be a float"
    assert isinstance(report["is_reproducible"], bool), "is_reproducible must be a boolean"
    assert isinstance(report["highest_cov_pair"], list), "highest_cov_pair must be a list"
    assert isinstance(report["highest_cov_value"], float), "highest_cov_value must be a float"

    # Check values
    assert report["is_reproducible"] is False, "Expected is_reproducible to be False based on the data."
    assert report["highest_cov_pair"] == ["beta", "delta"], f"Expected highest_cov_pair to be ['beta', 'delta'], got {report['highest_cov_pair']}"

    # max_abs_diff should be > 1e-5 for it to be not reproducible
    assert report["max_abs_diff"] > 1e-5, f"Expected max_abs_diff to be > 1e-5, got {report['max_abs_diff']}"

    # highest_cov_value should be positive and roughly around 1e-8
    assert report["highest_cov_value"] > 0, f"Expected highest_cov_value to be positive, got {report['highest_cov_value']}"

    # We can also check if the values are reasonably close to the expected ones (from seed 42)
    # expected max_abs_diff ~ 0.000390141
    # expected highest_cov_value ~ 1.01831e-08
    assert math.isclose(report["max_abs_diff"], 0.000390141, rel_tol=1e-2, abs_tol=1e-5), f"max_abs_diff value {report['max_abs_diff']} is not close to expected value."
    assert math.isclose(report["highest_cov_value"], 1.01831e-08, rel_tol=1e-2, abs_tol=1e-9), f"highest_cov_value value {report['highest_cov_value']} is not close to expected value."

def test_report_matches_csv_computation():
    with open(REPORT_PATH, 'r') as f:
        report = json.load(f)

    run1 = pd.read_csv(RUN1_PATH).select_dtypes(include='number')
    run2 = pd.read_csv(RUN2_PATH).select_dtypes(include='number')
    difference = run1 - run2
    expected_max = float(difference.abs().to_numpy().max())
    covariance = difference.cov()
    pairs = list(itertools.combinations(covariance.columns, 2))
    expected_pair_raw = max(pairs, key=lambda p: abs(float(covariance.loc[p[0], p[1]])))
    expected_pair = sorted(expected_pair_raw)
    expected_cov = float(covariance.loc[expected_pair_raw[0], expected_pair_raw[1]])

    assert math.isclose(report["max_abs_diff"], expected_max, rel_tol=1e-10, abs_tol=1e-15)
    assert report["is_reproducible"] is (expected_max < 1e-5)
    assert report["highest_cov_pair"] == expected_pair
    assert math.isclose(report["highest_cov_value"], expected_cov, rel_tol=1e-10, abs_tol=1e-15)
TEST_EOF

cat << 'HARNESS_EOF' > /tmp/test_script_behavior.py
import itertools
import json
import math
import os
import secrets
import subprocess
import sys

import numpy as np
import pandas as pd

SCRIPT = "/home/user/evaluate_reproducibility.py"
RUN1 = "/home/user/run1_output.csv"
RUN2 = "/home/user/run2_output.csv"
REPORT = "/home/user/test_report.json"
EXPECTED_KEYS = {"max_abs_diff", "is_reproducible", "highest_cov_pair", "highest_cov_value"}

original_run1 = open(RUN1, "rb").read()
original_run2 = open(RUN2, "rb").read()

def expected_from_files():
    first = pd.read_csv(RUN1).select_dtypes(include="number")
    second = pd.read_csv(RUN2).select_dtypes(include="number")
    difference = first - second
    maximum = float(difference.abs().to_numpy().max())
    covariance = difference.cov()
    pairs = list(itertools.combinations(covariance.columns, 2))
    raw_pair = max(pairs, key=lambda pair: abs(float(covariance.loc[pair[0], pair[1]])))
    return maximum, maximum < 1e-5, sorted(raw_pair), float(covariance.loc[raw_pair[0], raw_pair[1]])

def run_and_check():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    subprocess.run([sys.executable, SCRIPT], cwd="/home/user", check=True, timeout=30)
    assert os.path.isfile(REPORT), "The script did not create test_report.json"
    with open(REPORT, "r") as handle:
        report = json.load(handle)
    assert set(report) == EXPECTED_KEYS
    assert type(report["max_abs_diff"]) is float
    assert type(report["is_reproducible"]) is bool
    assert type(report["highest_cov_pair"]) is list
    assert type(report["highest_cov_value"]) is float
    expected_max, expected_reproducible, expected_pair, expected_cov = expected_from_files()
    assert math.isclose(report["max_abs_diff"], expected_max, rel_tol=1e-10, abs_tol=1e-15)
    assert report["is_reproducible"] is expected_reproducible
    assert report["highest_cov_pair"] == expected_pair
    assert math.isclose(report["highest_cov_value"], expected_cov, rel_tol=1e-10, abs_tol=1e-15)

try:
    rng = np.random.default_rng(secrets.randbits(64))
    rows = 173
    base = pd.DataFrame({
        "zeta": rng.normal(size=rows),
        "aardvark": rng.normal(size=rows),
        "middle": rng.normal(size=rows),
        "label": [f"row-{i}" for i in range(rows)],
    })

    # Exercise both sides of the strict reproducibility threshold. The shared
    # noise makes aardvark/zeta the unambiguous highest-covariance pair.
    for shared_scale, expected_flag in ((2e-7, True), (4e-4, False)):
        shared = rng.normal(scale=shared_scale, size=rows)
        changed = base.copy()
        changed["zeta"] = changed["zeta"] + shared + rng.normal(scale=shared_scale * 0.01, size=rows)
        changed["aardvark"] = changed["aardvark"] + shared + rng.normal(scale=shared_scale * 0.01, size=rows)
        changed["middle"] = changed["middle"] + rng.normal(scale=shared_scale * 0.02, size=rows)
        base.to_csv(RUN1, index=False)
        changed.to_csv(RUN2, index=False)
        run_and_check()
        with open(REPORT, "r") as handle:
            assert json.load(handle)["is_reproducible"] is expected_flag
finally:
    with open(RUN1, "wb") as handle:
        handle.write(original_run1)
    with open(RUN2, "wb") as handle:
        handle.write(original_run2)
    if os.path.isfile(SCRIPT):
        subprocess.run([sys.executable, SCRIPT], cwd="/home/user", check=True, timeout=30)
HARNESS_EOF

SCRIPT=/home/user/evaluate_reproducibility.py
if [ ! -f "$SCRIPT" ] || [ -L "$SCRIPT" ]; then
    status=1
else
    rm -f /home/user/test_report.json
    python3 "$SCRIPT" || status=1
fi

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ -f "$SCRIPT" ] && [ ! -L "$SCRIPT" ]; then
    python3 /tmp/test_script_behavior.py 2>&1 || status=1
else
    status=1
fi

# Confirm the restored original inputs still produce the required final report.
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
