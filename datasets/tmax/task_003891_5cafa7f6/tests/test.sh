#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest
import pandas as pd
from sklearn.metrics import r2_score

def test_pipeline_script_exists():
    """Check that the pipeline script was created."""
    assert os.path.isfile('/home/user/run_pipeline.py'), "The script /home/user/run_pipeline.py is missing."

def test_experiment_file_exists_and_valid():
    """Check that the experiment tracking file exists and is valid JSON."""
    experiment_path = '/home/user/experiment.json'
    assert os.path.isfile(experiment_path), f"The experiment file {experiment_path} is missing."

    with open(experiment_path, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {experiment_path} does not contain valid JSON.")

def test_target_encoder_fixed():
    """Check that the TargetEncoder from category_encoders can be imported and used."""
    try:
        from category_encoders import TargetEncoder
        # Try a simple fit_transform to ensure it works
        df = pd.DataFrame({'cat': ['a', 'b', 'a'], 'val': [1, 2, 3]})
        te = TargetEncoder(cols=['cat'])
        te.fit_transform(df[['cat']], df['val'])
    except NameError as e:
        pytest.fail(f"The category_encoders package still has a NameError: {e}. Did you fix the import bug?")
    except ImportError as e:
        pytest.fail(f"Failed to import TargetEncoder. Is the package installed correctly? Error: {e}")
    except Exception as e:
        pytest.fail(f"TargetEncoder failed during execution. Error: {e}")

def test_predictions_r2_score():
    """Evaluate the predictions against the hidden test labels using R-squared."""
    truth_path = '/tests/test_labels.csv'
    preds_path = '/home/user/predictions.csv'

    assert os.path.isfile(truth_path), f"Truth file {truth_path} is missing."
    assert os.path.isfile(preds_path), f"Predictions file {preds_path} is missing."

    truth = pd.read_csv(truth_path)
    preds = pd.read_csv(preds_path)

    assert 'predicted_income' in preds.columns, "predictions.csv must contain a 'predicted_income' column."
    assert len(truth) == len(preds), f"Expected {len(truth)} predictions, but got {len(preds)}."

    r2 = r2_score(truth['income'], preds['predicted_income'])
    assert r2 >= 0.65, f"R2 score {r2:.4f} is below the threshold of 0.65."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
