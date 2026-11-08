#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import time
import hashlib
import subprocess
import pytest
import pandas as pd

def anonymize(email):
    return hashlib.sha256(email.encode('utf-8')).hexdigest()[:16]

def get_expected_df():
    all_files = glob.glob("/app/data/activity_log_*.csv")
    assert len(all_files) == 50, f"Expected 50 CSV files, found {len(all_files)}"

    dfs = []
    for f in all_files:
        df = pd.read_csv(f)
        df = df[df['event_type'].isin(['video_stream', 'audio_stream'])].copy()
        df['date'] = df['timestamp'].str[:10]
        df['anon_user_id'] = df['user_id'].apply(anonymize)
        dfs.append(df[['date', 'anon_user_id', 'duration_ms']])

    combined = pd.concat(dfs, ignore_index=True)
    aggregated = combined.groupby(['date', 'anon_user_id'], as_index=False)['duration_ms'].sum()
    aggregated = aggregated.rename(columns={'duration_ms': 'total_duration_ms'})
    return aggregated.sort_values(['date', 'anon_user_id']).reset_index(drop=True)

def test_pipeline_execution_and_correctness():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} not found. Ensure you saved your solution."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable. Run 'chmod +x {script_path}'."

    start_time = time.time()
    result = subprocess.run([script_path], capture_output=True, text=True)
    end_time = time.time()

    runtime = end_time - start_time
    assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    output_path = "/home/user/daily_usage.parquet"
    assert os.path.isfile(output_path), f"Output file {output_path} not found. The script did not generate the expected Parquet file."

    try:
        actual_df = pd.read_parquet(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read parquet file at {output_path}. Error: {e}")

    expected_columns = ['date', 'anon_user_id', 'total_duration_ms']
    for col in expected_columns:
        assert col in actual_df.columns, f"Missing expected column '{col}' in output Parquet file."

    actual_df = actual_df[expected_columns].sort_values(['date', 'anon_user_id']).reset_index(drop=True)
    expected_df = get_expected_df()

    try:
        pd.testing.assert_frame_equal(actual_df, expected_df, check_dtype=False, check_exact=False)
    except AssertionError as e:
        pytest.fail(f"The generated Parquet file contents do not match the expected results:\n{e}")

    assert runtime <= 15.0, f"Performance threshold failed: runtime={runtime:.2f}s, threshold=15.0s. Your solution is too slow."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
