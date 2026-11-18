#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

# Generate Dataset
np.random.seed(42)
f1 = np.random.normal(0, 1, 100)
f2 = np.random.normal(0, 1, 100)
f3 = 3 * f1 - 2  # Perfectly collinear with f1
y = 2.5 * f1 - 1.2 * f2 + np.random.normal(0, 0.1, 100)

df = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'y': y})
df.to_csv('/home/user/dataset.csv', index=False)

# Generate Inference Script
inference_code = """import pandas as pd
import numpy as np
import time
import json
import sys

try:
    df = pd.read_csv('/home/user/cleaned_dataset.csv')
    X = df.drop(columns=['y']).values
    # Add intercept
    X = np.c_[np.ones(X.shape[0]), X]
    y = df['y'].values

    start = time.time()
    # Fails if matrix is singular (collinear features)
    beta = np.linalg.inv(X.T @ X) @ X.T @ y
    end = time.time()

    out = {
        "features": list(df.drop(columns=['y']).columns),
        "weights": [round(b, 4) for b in beta],
        "inference_time_ms": (end - start) * 1000
    }
    with open('/home/user/inference_results.json', 'w') as f:
        json.dump(out, f)
    print("Success: inference_results.json created.")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
"""

with open('/home/user/run_inference.py', 'w') as f:
    f.write(inference_code)

os.chmod('/home/user/run_inference.py', 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
