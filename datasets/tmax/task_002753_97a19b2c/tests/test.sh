#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pandas:pandas"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import hashlib
import subprocess
from functools import lru_cache

import pandas as pd
from datetime import datetime, timedelta
import pytest
from sklearn.metrics import mean_squared_error

@lru_cache(maxsize=1)
def generate_ground_truth():
    cmd = ["/app/log_emitter"]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)

    pattern = re.compile(r'^\[(.*?)\]\s+(\S+)\s+(\S+).*?bytes=(\d+)')

    seen_hashes = set()
    user_windows = {}
    user_counts = {}
    results = []

    total_lines_read = 0
    valid_parsed_lines = 0
    deduplicated_lines = 0

    for line in process.stdout:
        total_lines_read += 1
        match = pattern.search(line)
        if not match:
            continue

        timestamp_str, user_id, action, bytes_str = match.groups()

        try:
            dt = datetime.fromisoformat(timestamp_str)
            bytes_val = int(bytes_str)
        except (ValueError, OverflowError):
            continue

        valid_parsed_lines += 1

        hash_input = f"{timestamp_str}{user_id}{action}".encode('utf-8')
        md5_hash = hashlib.md5(hash_input).hexdigest()
        if md5_hash in seen_hashes:
            continue
        seen_hashes.add(md5_hash)
        deduplicated_lines += 1

        if user_id not in user_windows:
            user_windows[user_id] = []
            user_counts[user_id] = 0

        window = user_windows[user_id]
        window.append((dt, bytes_val))

        cutoff_time = dt - timedelta(minutes=5)
        while window and window[0][0] < cutoff_time:
            window.pop(0)

        avg_bytes = sum(b for _, b in window) / len(window)

        if user_counts[user_id] % 10 == 0:
            results.append({
                'timestamp': timestamp_str,
                'user_id': user_id,
                'action': action,
                'bytes': bytes_val,
                'rolling_avg_bytes': avg_bytes
            })

        user_counts[user_id] += 1

    process.stdout.close()
    return_code = process.wait()
    assert return_code == 0, f"log_emitter exited with status {return_code}"

    metrics = {
        'total_lines_read': total_lines_read,
        'valid_parsed_lines': valid_parsed_lines,
        'deduplicated_lines': deduplicated_lines,
    }
    return pd.DataFrame(results), metrics

def test_pipeline_results():
    agent_csv_path = "/home/user/rolling_averages.csv"
    assert os.path.exists(agent_csv_path), f"Agent output missing at {agent_csv_path}"

    agent_df = pd.read_csv(agent_csv_path)
    assert not agent_df.empty, "Agent CSV is empty"

    required_columns = ['timestamp', 'user_id', 'action', 'bytes', 'rolling_avg_bytes']
    for col in required_columns:
        assert col in agent_df.columns, f"Missing column {col} in agent CSV"

    gt_df, _ = generate_ground_truth()

    key_columns = ['timestamp', 'user_id']
    assert not gt_df.duplicated(subset=key_columns).any(), "Ground truth contains duplicate comparison keys"
    assert not agent_df.duplicated(subset=key_columns).any(), \
        "Agent CSV contains duplicate timestamp/user_id rows"
    assert len(agent_df) == len(gt_df), \
        f"Agent CSV has the wrong row count: expected {len(gt_df)}, got {len(agent_df)}"

    merged = pd.merge(
        gt_df,
        agent_df,
        on=key_columns,
        suffixes=('_gt', '_agent'),
        how='inner',
        validate='one_to_one'
    )

    assert len(merged) > 0, "No matching rows found between agent output and ground truth."

    coverage = len(merged) / len(gt_df)
    assert coverage >= 0.95, f"Agent output is missing too many rows. Coverage: {coverage:.2%}"

    assert (merged['action_gt'] == merged['action_agent']).all(), \
        "One or more sampled rows have an incorrect action"
    assert (merged['bytes_gt'] == merged['bytes_agent']).all(), \
        "One or more sampled rows have an incorrect bytes value"

    mse = mean_squared_error(
        merged['rolling_avg_bytes_gt'],
        merged['rolling_avg_bytes_agent']
    )
    assert mse <= 0.01, f"MSE {mse:.4f} exceeds threshold of 0.01"

def test_metrics_json():
    metrics_path = "/home/user/pipeline_metrics.json"
    assert os.path.exists(metrics_path), f"Metrics JSON missing at {metrics_path}"

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("pipeline_metrics.json is not valid JSON")

    assert "total_lines_read" in metrics, "Missing 'total_lines_read' in metrics"
    assert "valid_parsed_lines" in metrics, "Missing 'valid_parsed_lines' in metrics"
    assert "deduplicated_lines" in metrics, "Missing 'deduplicated_lines' in metrics"

    _, expected_metrics = generate_ground_truth()
    for key, expected_value in expected_metrics.items():
        assert metrics[key] == expected_value, \
            f"Incorrect metric {key}: expected {expected_value}, got {metrics[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
