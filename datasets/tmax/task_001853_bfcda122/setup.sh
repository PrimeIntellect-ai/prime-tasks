#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest numpy

python3 -c '
import os
import numpy as np
import json

os.makedirs("/home/user", exist_ok=True)

np.random.seed(42)
matrices = []
for _ in range(50):
    # Create a matrix that has some dominant singular value variance
    base = np.eye(10) * 8.0 
    noise = np.random.randn(10, 10) * 1.5
    mat = base + noise
    matrices.append(mat.tolist())

with open("/home/user/matrices.json", "w") as f:
    json.dump(matrices, f)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
