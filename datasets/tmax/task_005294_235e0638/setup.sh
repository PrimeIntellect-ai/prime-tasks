#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np
import pandas as pd
import json
import os
from scipy.integrate import simpson

os.makedirs('/home/user', exist_ok=True)

t = np.linspace(0, 10, 1000)
s1 = np.sin(t)
s2 = np.cos(t)
s3 = np.sin(2*t)
s4 = np.cos(2*t)
s5 = t / 10.0

df = pd.DataFrame({'time': t, 's1': s1, 's2': s2, 's3': s3, 's4': s4, 's5': s5})
df.to_csv('/home/user/signals.csv', index=False)

signals = [s1, s2, s3, s4, s5]
W = np.zeros((5, 5))
for i in range(5):
    for j in range(5):
        if i != j:
            W[i, j] = simpson(np.abs(signals[i] - signals[j]), x=t)
D = np.diag(np.sum(W, axis=1))
L = D - W
U, S, Vh = np.linalg.svd(L)
S_sorted = np.sort(S)

refs = {
    "model_alpha": (S_sorted + np.array([0.5, -0.2, 0.3, -0.4, 0.1])).tolist(),
    "model_beta": (S_sorted + np.array([-0.05, 0.02, -0.01, 0.04, -0.02])).tolist(),
    "model_gamma": (S_sorted + np.array([1.2, 0.8, -0.5, 0.6, 2.0])).tolist()
}
with open('/home/user/refs.json', 'w') as f:
    json.dump(refs, f)
EOF

    python3 /home/user/setup.py

    chmod -R 777 /home/user
