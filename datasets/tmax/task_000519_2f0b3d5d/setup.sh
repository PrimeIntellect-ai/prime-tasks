#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import math
import json

# Setup: Generate data.npy
np.random.seed(42)
data = np.random.uniform(0.1, 1.0, (100, 50, 50)).astype(np.float32)
# Introduce large numbers to cause float32 absorption errors
for i in range(50):
    for j in range(50):
        data[np.random.randint(0, 100), i, j] = 1e6

np.save('/home/user/data.npy', data)

# Verification Logic (what the agent is expected to compute)
data_reshaped = data.reshape(100, 2500)

errors = []
for j in range(2500):
    col = data_reshaped[:, j]

    # Unstable sum
    s = np.float32(0.0)
    for val in col:
        s += val

    # Stable sum
    stable_s = math.fsum(col)

    errors.append(float(s) - stable_s)

errors = np.array(errors)
max_abs_error = float(np.max(np.abs(errors)))

U, S, Vt = np.linalg.svd(data_reshaped, full_matrices=False)
vt0_abs_sum = float(np.sum(np.abs(Vt[0])))

np.random.seed(42)
means = []
for _ in range(1000):
    sample = np.random.choice(errors, size=len(errors), replace=True)
    means.append(np.mean(sample))

boot_ci_lower = float(np.percentile(means, 2.5))
boot_ci_upper = float(np.percentile(means, 97.5))

expected_results = {
    "max_abs_error": max_abs_error,
    "svd_vt0_abs_sum": vt0_abs_sum,
    "boot_ci_lower": boot_ci_lower,
    "boot_ci_upper": boot_ci_upper
}

with open('/tmp/expected_results.json', 'w') as f:
    json.dump(expected_results, f)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
