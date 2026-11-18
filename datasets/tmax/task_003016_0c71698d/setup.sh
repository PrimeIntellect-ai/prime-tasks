#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg wget curl git espeak-ng
    pip3 install pytest numpy

    mkdir -p /app

    # Generate the audio memo
    espeak-ng -w /app/audio_memo.wav "The data is heavily corrupted by sensor spikes. Please discard all vectors with an L2 norm strictly greater than 15.2 before computing the baseline averages."

    # Generate the dataset and truth
    cat << 'EOF' > /app/generate_data.py
import numpy as np
import struct

# Set random seed for reproducible truth
np.random.seed(42)

num_records = 1000000
dim = 10
threshold = 15.2

# Generate random data: N(0, 5) meaning norms will average around sqrt(10 * 25) = 15.8
data = np.random.normal(0, 5.0, (num_records, dim))

# Calculate norms
norms = np.linalg.norm(data, axis=1)

# Filter data
valid_data = data[norms <= threshold]

# Calculate mean
true_mean = np.mean(valid_data, axis=0)

# Save binary data
with open('/app/sensor_data.bin', 'wb') as f:
    f.write(data.astype(np.float64).tobytes())

# Save ground truth for verifier
np.savetxt('/app/truth.csv', [true_mean], delimiter=',')
EOF

    python3 /app/generate_data.py

    # Create the verifier script
    cat << 'EOF' > /app/verify.py
import numpy as np
import sys

try:
    agent_data = np.loadtxt('/home/user/result.csv', delimiter=',')
    truth_data = np.loadtxt('/app/truth.csv', delimiter=',')

    if agent_data.shape != (10,):
        print(f"Shape mismatch: {agent_data.shape}")
        sys.exit(1)

    rmse = np.sqrt(np.mean((agent_data - truth_data)**2))
    print(f"RMSE: {rmse}")

    if rmse <= 0.001:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Verification failed: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
