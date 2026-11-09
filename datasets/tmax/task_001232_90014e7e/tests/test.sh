#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import pandas as pd
import numpy as np

def test_mre_file():
    mre_path = "/home/user/mre.wal"
    assert os.path.exists(mre_path), f"MRE file is missing at {mre_path}"
    with open(mre_path, 'r') as f:
        lines = f.read().splitlines()
    assert len(lines) == 3, f"MRE file {mre_path} should have exactly 3 lines, found {len(lines)}"

def test_recovered_db_exists():
    db_path = "/home/user/recovered_db.csv"
    assert os.path.exists(db_path), f"Recovered DB file is missing at {db_path}"
    assert os.path.getsize(db_path) > 0, f"Recovered DB file {db_path} is empty"

def test_analyze_script_exists_and_executable():
    script_path = "/home/user/analyze.sh"
    assert os.path.exists(script_path), f"Analyze script is missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Analyze script at {script_path} is not executable"

def test_uptime_results_metric():
    results_path = "/home/user/uptime_results.csv"
    truth_path = "/tests/truth_uptime.csv"

    assert os.path.exists(results_path), f"Results file missing at {results_path}"
    assert os.path.exists(truth_path), f"Truth file missing at {truth_path}"

    truth = pd.read_csv(truth_path, names=['server_id', 'uptime'])
    pred = pd.read_csv(results_path, names=['server_id', 'uptime'])

    merged = pd.merge(truth, pred, on='server_id')
    assert len(merged) > 0, "No matching server_ids between truth and prediction"
    assert len(merged) == len(truth), f"Expected {len(truth)} servers, but found {len(merged)} matching servers in output"

    mae = np.mean(np.abs(merged['uptime_x'] - merged['uptime_y']))
    assert mae <= 0.05, f"MAE {mae} exceeds threshold of 0.05"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
