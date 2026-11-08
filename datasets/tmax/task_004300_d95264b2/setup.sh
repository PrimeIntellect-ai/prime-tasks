#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import numpy as np
import pandas as pd

data_dir = '/home/user/mlops_data'
preds_dir = os.path.join(data_dir, 'predictions')
os.makedirs(preds_dir, exist_ok=True)

np.random.seed(42)
ids = np.arange(1, 101)
true_vals = np.random.normal(10, 2, 100)

# Ground truth
pd.DataFrame({'id': ids, 'true_value': true_vals}).to_csv(os.path.join(data_dir, 'ground_truth.csv'), index=False)

# Model A: Decent
pred_a = true_vals + np.random.normal(0, 0.5, 100)
pd.DataFrame({'id': ids, 'pred_value': pred_a}).to_csv(os.path.join(preds_dir, 'model_A.csv'), index=False)

# Model B: Best model
pred_b = true_vals + np.random.normal(0, 0.1, 100)
pd.DataFrame({'id': ids, 'pred_value': pred_b}).to_csv(os.path.join(preds_dir, 'model_B.csv'), index=False)

# Model C: Terrible MSE, but highly similar vector to Model B (scaled)
pred_c = pred_b * 1.5 
pd.DataFrame({'id': ids, 'pred_value': pred_c}).to_csv(os.path.join(preds_dir, 'model_C.csv'), index=False)

# Model D: Random
pred_d = np.random.normal(10, 2, 100)
pd.DataFrame({'id': ids, 'pred_value': pred_d}).to_csv(os.path.join(preds_dir, 'model_D.csv'), index=False)
"

    chmod -R 777 /home/user
