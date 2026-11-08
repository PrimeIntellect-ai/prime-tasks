#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import numpy as np
import pandas as pd
import pytest
from sklearn.metrics import mean_squared_error

def test_predict_script():
    script_path = "/home/user/predict.sh"
    test_features = "/home/user/data/hidden_test_features.csv"
    output_preds = "/home/user/hidden_test_preds.txt"

    # Check if predict.sh exists
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    # Run the script
    with open(output_preds, "w") as f_out:
        result = subprocess.run(
            ["/bin/bash", script_path, test_features],
            stdout=f_out,
            stderr=subprocess.PIPE,
            text=True
        )

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert os.path.exists(output_preds), f"Output file {output_preds} was not created."
    assert os.path.getsize(output_preds) > 0, f"Output file {output_preds} is empty."

    # Load predictions
    try:
        preds = pd.read_csv(output_preds, header=None).values.flatten()
    except Exception as e:
        pytest.fail(f"Failed to read predictions from {output_preds}: {e}")

    # Derive the held-out labels from the same generation rule used by setup.
    try:
        features = pd.read_csv(test_features, header=None).to_numpy(dtype=float)
        means = np.rint(np.nanmean(features, axis=0)).astype(int)
        imputed = np.where(np.isnan(features), means, features)
        labels = (imputed[:, 0] * 2) + (imputed[:, 1] * 3) - imputed[:, 2] + imputed[:, 3]
    except Exception as e:
        pytest.fail(f"Failed to derive held-out labels: {e}")

    assert len(preds) == len(labels), f"Number of predictions ({len(preds)}) does not match number of labels ({len(labels)})."

    # Calculate MSE
    mse = mean_squared_error(labels, preds)

    # Assert threshold
    assert mse <= 1.0, f"MSE is {mse:.4f}, which is > 1.0. Imputation strategy may be suboptimal or incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
