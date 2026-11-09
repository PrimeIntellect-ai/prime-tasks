#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas scipy matplotlib

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 2500
w = 0.35
mu1, std1 = 2.0, 0.8
mu2, std2 = 7.5, 1.2

samples1 = np.random.normal(mu1, std1, int(n_samples * w))
samples2 = np.random.normal(mu2, std2, int(n_samples * (1 - w)))
data = np.concatenate([samples1, samples2])
np.random.shuffle(data)

df = pd.DataFrame({"value": data})
df.to_csv("/home/user/data.csv", index=False)
EOF

python3 /tmp/generate_data.py

chmod -R 777 /home/user
