#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn joblib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import joblib
from sklearn.linear_model import Ridge
import os

os.makedirs('/home/user/models', exist_ok=True)
np.random.seed(42)

# Generate data
X = np.random.rand(100, 10)
true_weights = np.random.rand(10)
y = X @ true_weights + np.random.rand(100) * 0.1

np.save('/home/user/X.npy', X)
np.save('/home/user/y_target.npy', y)

# Train models with different levels of noise
m1 = Ridge(alpha=1.0).fit(X, y + np.random.rand(100) * 5.0) # Poor model
m2 = Ridge(alpha=0.1).fit(X, y + np.random.rand(100) * 2.0) # Mediocre model
m3 = Ridge(alpha=0.01).fit(X, y)                            # Best model

# Save models
joblib.dump(m1, '/home/user/models/model_alpha.pkl')
joblib.dump(m2, '/home/user/models/model_beta.pkl')
joblib.dump(m3, '/home/user/models/model_gamma.pkl')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
