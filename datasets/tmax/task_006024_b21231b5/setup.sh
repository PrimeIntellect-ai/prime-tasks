#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np

# Ground truth parameters
true_C = 0.55
true_k = 0.3
gc_0 = 0.40

times = np.array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
gcs = true_C + (gc_0 - true_C) * np.exp(-true_k * times)
# Add small noise
np.random.seed(123)
gcs_noisy = gcs + np.random.normal(0, 0.005, size=len(times))

# Make sure t=0 matches gc_0 exactly for the formulation
gcs_noisy[0] = gc_0

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/observations.csv', 'w') as f:
    f.write("time,gc_content\n")
    for t, gc in zip(times, gcs_noisy):
        f.write(f"{t},{gc:.5f}\n")
EOF

python3 /tmp/gen_data.py
rm /tmp/gen_data.py

chmod -R 777 /home/user
