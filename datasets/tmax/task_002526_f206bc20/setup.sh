#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import numpy as np

os.makedirs('/home/user/artifacts', exist_ok=True)

# Generate 2,500,000 random floats
np.random.seed(42)
num_floats = 2500000
truth_data = np.random.uniform(-10.0, 10.0, num_floats).astype(np.float32)

# Create inference data with some noise
noise = np.random.normal(0, 0.5, num_floats).astype(np.float32)
inference_data = truth_data + noise

# Calculate exact metrics for validation
diff = np.abs(truth_data - inference_data)
expected_mae = np.mean(diff)
expected_max_ae = np.max(diff)

# Write to binary files
with open('/home/user/artifacts/truth.bin', 'wb') as f:
    f.write(truth_data.tobytes())

with open('/home/user/artifacts/inference.bin', 'wb') as f:
    f.write(inference_data.tobytes())

# Save expected metrics for verification script
with open('/home/user/expected_metrics.txt', 'w') as f:
    f.write(f"{expected_mae},{expected_max_ae}")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
