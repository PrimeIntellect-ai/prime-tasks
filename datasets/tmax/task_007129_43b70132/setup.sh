#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import json
import os

# Create customer_data.csv
data = {
    'id': [101, 102, 103, 104, 105, 106, 107, 108],
    'age': [25, 15, 95, 45, 30, -5, 50, 42],
    'income': [45000, 75000, np.nan, 55000, 120000, np.nan, 61000, 58000],
    'score_A': [80, 90, 70, 85, 60, 95, 50, 75],
    'score_B': [75, 85, 65, 90, 55, 88, 60, 80],
    'category': ['A', 'B', 'C', 'A', 'A', 'B', 'C', 'B']
}
df = pd.DataFrame(data)
df.to_csv('/home/user/customer_data.csv', index=False)

# Create model_config.json
model_config = {
    "intercept": -2.5,
    "weights": {
        "age": 0.02,
        "combined_score": 0.05,
        "income_bracket": 0.8,
        "cat_A": 0.5,
        "cat_B": -0.3,
        "cat_C": 0.0
    }
}
with open('/home/user/model_config.json', 'w') as f:
    json.dump(model_config, f, indent=4)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
