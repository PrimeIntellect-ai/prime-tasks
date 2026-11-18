#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user/dataset
    mkdir -p /home/user/positive_cases
    mkdir -p /home/user/negative_cases

    python3 -c "
import numpy as np
import os

np.random.seed(42)
os.makedirs('/home/user/dataset', exist_ok=True)
os.makedirs('/home/user/positive_cases', exist_ok=True)
os.makedirs('/home/user/negative_cases', exist_ok=True)

W1 = np.random.randn(10, 5).astype(np.float32)
b1 = np.random.randn(5).astype(np.float32)
W2 = np.random.randn(5, 1).astype(np.float32)
b2 = np.random.randn(1).astype(np.float32)

np.savez('/home/user/model_weights.npz', W1=W1, b1=b1, W2=W2, b2=b2)

for i in range(50):
    x = np.random.randn(10).astype(np.float32)
    np.save(f'/home/user/dataset/sample_{i}.npy', x)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
