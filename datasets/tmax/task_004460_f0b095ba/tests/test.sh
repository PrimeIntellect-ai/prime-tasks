#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

def test_final_database_exists():
    db_path = '/home/user/clean_events.db'
    assert os.path.exists(db_path), f"Database file not found at {db_path}"
    assert os.path.isfile(db_path), f"{db_path} is not a file"

def test_f1_score_of_clean_events():
    db_path = '/home/user/clean_events.db'
    gt_path = '/tests/ground_truth_ids.txt'

    assert os.path.exists(db_path), f"Database file not found at {db_path}"
    assert os.path.exists(gt_path), f"Ground truth file not found at {gt_path}"

    # Read true IDs
    with open(gt_path, 'r') as f:
        true_ids = set(line.strip() for line in f if line.strip())

    assert len(true_ids) > 0, "Ground truth IDs file is empty"

    # Connect to DB and read predicted IDs
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # Check if table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='events'")
        table_exists = cursor.fetchone()
        assert table_exists is not None, "Table 'events' does not exist in the database"

        cursor.execute("SELECT event_id FROM events")
        pred_ids = set(str(row[0]) for row in cursor.fetchall())
    except sqlite3.Error as e:
        pytest.fail(f"SQLite error: {e}")
    finally:
        conn.close()

    # Calculate metrics
    tp = len(pred_ids & true_ids)
    fp = len(pred_ids - true_ids)
    fn = len(true_ids - pred_ids)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    threshold = 0.95
    assert f1 >= threshold, (
        f"F1 Score {f1:.4f} is below the threshold of {threshold}. "
        f"True Positives: {tp}, False Positives: {fp}, False Negatives: {fn}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
