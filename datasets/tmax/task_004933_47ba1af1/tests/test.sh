#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE=/tests/.hidden_truth.csv
SCRIPT=/home/user/pipeline.sh
RESULTS=/home/user/results.csv

# Keep the test-only oracle unreadable by the submitted pipeline.
if [ ! -f "$ORACLE" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
chmod 600 "$ORACLE"

# Require the submitted artifact to regenerate the output.
if [ ! -f "$SCRIPT" ] || [ ! -x "$SCRIPT" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
rm -f "$RESULTS"
if ! timeout 180s runuser -u user -- bash -c 'cd /home/user && exec ./pipeline.sh'; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import numpy as np

def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Pipeline script at {script_path} is not executable"

def test_results_csv_exists():
    results_path = "/home/user/results.csv"
    assert os.path.isfile(results_path), f"Results CSV not found at {results_path}"

def test_results_metric_threshold():
    results_path = "/home/user/results.csv"
    truth_path = "/tests/.hidden_truth.csv"

    assert os.path.isfile(results_path), f"Results CSV missing: {results_path}"
    assert os.path.isfile(truth_path), f"Hidden truth CSV missing: {truth_path}"

    try:
        df_agent = pd.read_csv(results_path)
    except Exception as e:
        assert False, f"Failed to read {results_path} as CSV: {e}"

    try:
        df_truth = pd.read_csv(truth_path)
    except Exception as e:
        assert False, f"Failed to read {truth_path} as CSV: {e}"

    required_columns = ['time_sec', 'sensor_a', 'intensity', 'anomaly_flag']
    for col in required_columns:
        assert col in df_agent.columns, f"Missing required column '{col}' in {results_path}"

    # Require complete, one-to-one coverage rather than allowing a partial merge.
    assert len(df_agent) == len(df_truth), \
        f"Expected {len(df_truth)} data rows, found {len(df_agent)}"
    assert df_agent['time_sec'].notna().all(), "time_sec contains missing values"
    assert df_agent['time_sec'].is_unique, "time_sec values must be unique"
    assert set(df_agent['time_sec'].tolist()) == set(df_truth['time_sec'].tolist()), \
        "Submitted time_sec values do not exactly cover the expected seconds"

    # Merge to compare
    df_eval = pd.merge(df_truth, df_agent, on='time_sec', suffixes=('_true', '_pred'))

    assert not df_eval.empty, "Merged dataframe is empty. Ensure 'time_sec' matches the expected values."
    assert len(df_eval) == len(df_truth), "Merged dataframe does not have complete expected coverage"

    # Calculate Intensity MAE
    mae_intensity = np.abs(df_eval['intensity_pred'] - df_eval['intensity_true']).mean()

    # Calculate Anomaly Accuracy
    accuracy = (df_eval['anomaly_flag_pred'] == df_eval['anomaly_flag_true']).mean()

    # Calculate final score
    score = accuracy - (mae_intensity / 255.0)

    threshold = 0.85
    assert score >= threshold, f"Score {score:.4f} is below threshold {threshold} (Accuracy: {accuracy:.4f}, MAE: {mae_intensity:.4f})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
