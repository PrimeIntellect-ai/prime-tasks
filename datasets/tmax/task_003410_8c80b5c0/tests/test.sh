#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
from sklearn.metrics import f1_score
import pytest

def test_predictions_exist():
    assert os.path.isfile('/home/user/test_predictions.csv'), "The file /home/user/test_predictions.csv does not exist. Ensure your pipeline script generates this file."

def test_f1_score_threshold():
    preds_path = '/home/user/test_predictions.csv'
    truth_path = '/tests/ground_truth.csv'

    assert os.path.isfile(preds_path), f"{preds_path} is missing."
    assert os.path.isfile(truth_path), f"{truth_path} is missing."

    try:
        preds = pd.read_csv(preds_path)
    except Exception as e:
        pytest.fail(f"Failed to read predictions CSV: {e}")

    try:
        truth = pd.read_csv(truth_path)
    except Exception as e:
        pytest.fail(f"Failed to read ground truth CSV: {e}")

    assert 'id' in preds.columns, "Column 'id' is missing in /home/user/test_predictions.csv."
    assert 'label' in preds.columns, "Column 'label' is missing in /home/user/test_predictions.csv."

    merged = pd.merge(truth, preds, on='id')
    assert not merged.empty, "Merged dataframe is empty. Ensure the 'id' column in your predictions matches the test documents."

    # 'label_x' comes from truth, 'label_y' comes from preds
    score = f1_score(merged['label_x'], merged['label_y'], average='macro')

    assert score >= 0.85, f"Macro F1 Score is {score:.4f}, which is below the required threshold of 0.85. The ETL bug might not be fully fixed or hyperparameter tuning was insufficient."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
