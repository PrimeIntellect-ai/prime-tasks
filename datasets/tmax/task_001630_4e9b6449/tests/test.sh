#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score


def test_predict_script_accuracy():
    script_path = "/home/user/predict.py"
    assert os.path.exists(script_path), f"Expected script {script_path} not found."

    # Generate a fresh hidden test set on every verifier run so predictions
    # cannot be hardcoded for a known seed or fixed ID-to-label mapping.
    seed = int.from_bytes(os.urandom(8), "big") % (2**32)
    rng = np.random.RandomState(seed)
    n = 1000
    id_offset = int(rng.randint(100000, 1000000000))
    ids = id_offset + rng.permutation(n)
    s1 = rng.randn(n) * 3
    s2 = rng.randn(n) * 3
    s3 = rng.randn(n) * 3
    s4 = rng.randn(n) * 3

    # True logic: label is 1 if (s1 * 1.5) + (s2 * s2) - s3 + (s4 * 0.5) > 10.0
    score = (s1 * 1.5) + (s2 * s2) - s3 + (s4 * 0.5)
    true_label = (score > 10.0).astype(int)

    df = pd.DataFrame({'id': ids, 'sensor1': s1, 'sensor2': s2, 'sensor3': s3, 'sensor4': s4})

    # Inject missing values (5% per column)
    for col in ['sensor1', 'sensor2', 'sensor3', 'sensor4']:
        mask = rng.rand(n) < 0.05
        df.loc[mask, col] = np.nan

    # Inject extreme outliers in sensor3 (5%)
    outlier_mask = rng.rand(n) < 0.05
    df.loc[outlier_mask, 'sensor3'] = 15000.0

    test_csv = "/tmp/test_hidden.csv"
    df.to_csv(test_csv, index=False)

    # Run the predict script
    cwd = "/home/user"
    pred_csv = os.path.join(cwd, "predictions.csv")
    if os.path.exists(pred_csv):
        os.remove(pred_csv)

    result = subprocess.run(
        ["python3", script_path, test_csv],
        cwd=cwd,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"predict.py failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.exists(pred_csv), f"{pred_csv} was not created by predict.py"

    # Evaluate predictions
    preds = pd.read_csv(pred_csv)
    assert 'id' in preds.columns and 'label' in preds.columns, "predictions.csv must contain 'id' and 'label' columns"

    truth_df = pd.DataFrame({'id': ids, 'true_label': true_label})
    merged = truth_df.merge(preds, on='id')
    assert len(merged) == n, f"predictions.csv contains {len(merged)} valid ids, expected {n}"

    acc = accuracy_score(merged['true_label'], merged['label'])
    assert acc >= 0.95, f"Accuracy {acc:.4f} is below threshold 0.95"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
