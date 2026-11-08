#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import time
from collections import defaultdict, deque

import pandas as pd
import pytest


def derive_expected(log_path):
    required_columns = ["cluster_id", "timestamp", "duration_seconds", "rolling_avg"]
    histories = defaultdict(lambda: deque(maxlen=7))
    anomalies = []

    with open(log_path, "r", encoding="utf-8") as source:
        for line in source:
            if not line.strip():
                continue
            record = json.loads(line)
            cluster_id = record["cluster_id"]
            duration = float(record["duration_seconds"])
            history = histories[cluster_id]

            if len(history) == 7:
                rolling_avg = sum(history) / 7.0
                if duration > 2.5 * rolling_avg:
                    anomalies.append({
                        "cluster_id": cluster_id,
                        "timestamp": record["timestamp"],
                        "duration_seconds": duration,
                        "rolling_avg": rolling_avg,
                    })

            history.append(duration)

    return pd.DataFrame(anomalies, columns=required_columns)


def test_execution_time_and_output():
    binary_path = "/app/backup-analyzer/target/release/backup-analyzer"
    assert os.path.isfile(binary_path), (
        f"Optimized release binary not found at {binary_path}. "
        "Did you run 'cargo build --release'?"
    )

    start_time = time.time()
    result = subprocess.run(
        [binary_path],
        cwd="/app/backup-analyzer",
        capture_output=True,
        text=True,
    )
    end_time = time.time()

    assert result.returncode == 0, (
        f"Binary execution failed with output:\n{result.stderr}\n{result.stdout}"
    )

    execution_time = end_time - start_time
    assert execution_time <= 1.5, (
        f"Execution time was {execution_time:.3f} seconds, "
        "which exceeds the threshold of 1.5 seconds."
    )

    anomalies_path = "/home/user/anomalies.csv"
    logs_path = "/home/user/backup_logs.jsonl"
    assert os.path.isfile(anomalies_path), f"Output file {anomalies_path} is missing."
    assert os.path.isfile(logs_path), f"Input file {logs_path} is missing."

    df_actual = pd.read_csv(anomalies_path)
    df_expected = derive_expected(logs_path)

    required_columns = ["cluster_id", "timestamp", "duration_seconds", "rolling_avg"]
    for col in required_columns:
        assert col in df_actual.columns, f"Column '{col}' is missing from anomalies.csv"

    df_actual = df_actual.sort_values(
        by=["timestamp", "cluster_id"], ascending=[False, True]
    ).reset_index(drop=True)
    df_expected = df_expected.sort_values(
        by=["timestamp", "cluster_id"], ascending=[False, True]
    ).reset_index(drop=True)

    try:
        pd.testing.assert_frame_equal(
            df_actual[required_columns],
            df_expected[required_columns],
            check_exact=False,
            rtol=1e-3,
        )
    except AssertionError as error:
        pytest.fail(
            "The generated anomalies.csv does not match the expected output. "
            f"Details:\n{error}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
