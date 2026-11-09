#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/model /home/user/scripts /home/user/output /tmp/truth

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
import pandas as pd

base_dir = "/home/user"
data_dir = os.path.join(base_dir, "data")
model_dir = os.path.join(base_dir, "model")

np.random.seed(42)
n_samples = 500
ids = np.arange(1, n_samples + 1)
sensor_A = np.random.normal(0, 1, n_samples)
sensor_B = np.random.normal(5, 2, n_samples)
sensor_C = np.random.normal(-2, 1.5, n_samples)

df = pd.DataFrame({'id': ids, 'sensor_A': sensor_A, 'sensor_B': sensor_B, 'sensor_C': sensor_C})
df.to_csv(os.path.join(data_dir, "input.csv"), index=False)

network = {
  "layers": [
    {
      "type": "dense",
      "weights": [
        [0.2, 0.8, -0.5, 1.0],
        [-1.5, 0.3, 0.2, 0.1],
        [0.5, -0.5, 0.5, -0.5]
      ],
      "biases": [0.1, -0.2, 0.3, -0.1],
      "activation": "relu"
    },
    {
      "type": "dense",
      "weights": [
        [0.8],
        [-0.5],
        [1.2],
        [-1.0]
      ],
      "biases": [-0.5],
      "activation": "sigmoid"
    }
  ]
}

with open(os.path.join(model_dir, "network.json"), 'w') as f:
    json.dump(network, f, indent=2)

X = df[['sensor_A', 'sensor_B', 'sensor_C']].values
W1 = np.array(network['layers'][0]['weights'])
b1 = np.array(network['layers'][0]['biases'])
Z1 = np.dot(X, W1) + b1
A1 = np.maximum(0, Z1)

W2 = np.array(network['layers'][1]['weights'])
b2 = np.array(network['layers'][1]['biases'])
Z2 = np.dot(A1, W2) + b2
A2 = 1 / (1 + np.exp(-Z2))

predictions = (A2 >= 0.5).astype(int).flatten()

expected_df = pd.DataFrame({'id': ids, 'prediction': predictions})
expected_df.to_csv("/tmp/truth/expected_predictions.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
    chmod -R 777 /tmp/truth
