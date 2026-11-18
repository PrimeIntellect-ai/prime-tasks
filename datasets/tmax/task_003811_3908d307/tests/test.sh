#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import pandas as pd
from sklearn.metrics import mean_squared_error
import pytest

def test_predict_script_exists():
    assert os.path.isfile('/home/user/predict.py'), "predict.py not found at /home/user/predict.py"

def test_model_exists():
    assert os.path.isfile('/home/user/student_model.pkl'), "student_model.pkl not found at /home/user/student_model.pkl"

def test_mse_threshold():
    # Attempt to import sentence_transformers which the agent should have installed
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        pytest.fail("sentence-transformers is not installed. The task requires it for embeddings.")

    test_csv_path = '/test/hidden_texts.csv'
    assert os.path.isfile(test_csv_path), f"Hidden test texts missing at {test_csv_path}"

    df_test = pd.read_csv(test_csv_path)

    # 1. Generate embeddings for the hidden test set
    model = SentenceTransformer('all-MiniLM-L6-v2')
    embeddings = model.encode(df_test['text'].tolist())

    emb_path = '/test/hidden_embeddings.csv'
    pd.DataFrame(embeddings).to_csv(emb_path, index=False, header=False)

    # 2. Run the legacy oracle to get the true scores
    gt_path = '/test/ground_truth_scores.csv'
    scorer_result = subprocess.run(
        ['/app/legacy_scorer', emb_path, gt_path],
        capture_output=True, text=True
    )
    assert scorer_result.returncode == 0, f"Legacy scorer failed to run: {scorer_result.stderr}"
    assert os.path.isfile(gt_path), "Legacy scorer did not output the ground truth file."

    gt_scores = pd.read_csv(gt_path, header=None, names=['score'])
    df_test['score'] = gt_scores['score']

    # 3. Run the student's inference script
    pred_path = '/test/student_predictions.csv'
    if os.path.exists(pred_path):
        os.remove(pred_path)

    predict_result = subprocess.run(
        [sys.executable, '/home/user/predict.py', test_csv_path, pred_path],
        capture_output=True, text=True
    )
    assert predict_result.returncode == 0, f"predict.py execution failed:\nSTDOUT: {predict_result.stdout}\nSTDERR: {predict_result.stderr}"
    assert os.path.isfile(pred_path), f"predict.py did not create the output file at {pred_path}"

    # 4. Evaluate the predictions
    preds = pd.read_csv(pred_path)
    assert 'id' in preds.columns, "Output CSV missing 'id' column."
    assert 'score' in preds.columns, "Output CSV missing 'score' column."

    merged = pd.merge(preds, df_test, on='id', suffixes=('_pred', '_true'))
    assert len(merged) == len(df_test), "Mismatch in number of predicted rows versus input rows."

    mse = mean_squared_error(merged['score_true'], merged['score_pred'])
    assert mse <= 0.01, f"MSE is {mse:.5f}, which exceeds the threshold of 0.01."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
