#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn jsonschema

    useradd -m -s /bin/bash user || true

    # Generate data.csv
    python3 -c "
import pandas as pd
from sklearn.datasets import make_regression
import os

os.makedirs('/home/user', exist_ok=True)
X, y = make_regression(n_samples=150, n_features=4, noise=0.1, random_state=42)
df = pd.DataFrame(X, columns=['f1', 'f2', 'f3', 'f4'])
df['target'] = y
df.to_csv('/home/user/data.csv', index=False)
"

    # Generate schema.json
    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "model": {
      "type": "string",
      "pattern": "^BayesianRidge$"
    },
    "best_alpha_1": {
      "type": "number"
    },
    "best_lambda_1": {
      "type": "number"
    },
    "cv_score": {
      "type": "number"
    }
  },
  "required": [
    "model",
    "best_alpha_1",
    "best_lambda_1",
    "cv_score"
  ],
  "additionalProperties": false
}
EOF

    chmod -R 777 /home/user
