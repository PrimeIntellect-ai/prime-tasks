#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    python3 -c '
import numpy as np
import os

os.makedirs("/home/user", exist_ok=True)

np.random.seed(42)
n_samples = 200
n_features = 120

X = np.random.randn(n_samples, n_features)
y = np.random.randint(0, 2, n_samples)

for i in range(n_samples):
    if y[i] == 1:
        X[i, 0:8] += 2.0
    else:
        X[i, 0:8] -= 2.0

np.savetxt("/home/user/sensor_data.csv", np.hstack((X, y.reshape(-1, 1))), delimiter=",", fmt="%.6f")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
