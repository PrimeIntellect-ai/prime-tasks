#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pandas as pd
from sklearn.metrics import f1_score


def test_pipeline_exists():
    """Check that the pipeline script was created."""
    assert os.path.isfile("/home/user/pipeline.py"), "The file /home/user/pipeline.py is missing."


def test_anomalies_parquet_exists():
    """Check that the output parquet file was created."""
    assert os.path.isfile("/home/user/anomalies.parquet"), "The file /home/user/anomalies.parquet is missing."


def test_anomalies_schema():
    """Check that the parquet file has the correct schema."""
    df_pred = pd.read_parquet('/home/user/anomalies.parquet')
    expected_columns = {
        'request_id', 'timestamp', 'url', 'status_code',
        'nginx_latency', 'flask_latency', 'anomaly_reason'
    }
    actual_columns = set(df_pred.columns)
    missing_columns = expected_columns - actual_columns
    assert not missing_columns, f"Missing columns in anomalies.parquet: {missing_columns}"


def test_anomaly_detection_f1_score():
    """Evaluate the F1-score of the anomaly detection."""
    try:
        df_pred = pd.read_parquet('/home/user/anomalies.parquet')
        pred_ids = set(df_pred['request_id'].tolist())
    except Exception:
        pred_ids = set()

    df_true = pd.read_parquet('/tests/ground_truth_anomalies.parquet')
    true_ids = set(df_true['request_id'].tolist())

    all_ids = set(pd.read_parquet('/tests/all_requests.parquet')['request_id'].tolist())

    y_true = [1 if req_id in true_ids else 0 for req_id in all_ids]
    y_pred = [1 if req_id in pred_ids else 0 for req_id in all_ids]

    score = f1_score(y_true, y_pred)
    assert score >= 0.95, f"F1-score for anomaly detection is {score:.4f}, expected >= 0.95"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
