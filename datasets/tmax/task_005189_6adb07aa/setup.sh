#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy scikit-learn

    mkdir -p /home/user
    cat << 'EOF' > /home/user/model_pipeline.py
import numpy as np
import json
from sklearn.model_selection import cross_val_score, KFold
from sklearn.feature_selection import SelectKBest, f_regression
from sklearn.linear_model import Ridge

# DO NOT MODIFY DATA GENERATION
np.random.seed(42)
X = np.random.randn(100, 1000)
y = np.random.randn(100)

# --- Fix the leakage below this line ---

# The leak: Feature selection is applied to the entire dataset
selector = SelectKBest(score_func=f_regression, k=10)
X_selected = selector.fit_transform(X, y)

model = Ridge()
kf = KFold(n_splits=5, shuffle=True, random_state=42)
scores = cross_val_score(model, X_selected, y, cv=kf, scoring='r2')

result = {"mean_r2": scores.mean()}
with open('/home/user/metrics.json', 'w') as f:
    json.dump(result, f)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
