#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest numpy

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/lab_memo.wav "Initialize the mixture model means at 1.0, 2.0, and 4.0. Stop the iterations when the log likelihood changes by less than 0.0001."

    # Create setup script for data generation
    cat << 'EOF' > /app/setup_data.py
import numpy as np

# True parameters
true_means = [1.25, 2.80, 4.15]
true_stds = [0.2, 0.3, 0.15]
true_weights = [0.4, 0.35, 0.25]
n_samples = 10000

np.random.seed(42)
choices = np.random.choice(3, size=n_samples, p=true_weights)
data = np.zeros(n_samples)

for i in range(3):
    mask = choices == i
    data[mask] = np.random.normal(loc=true_means[i], scale=true_stds[i], size=np.sum(mask))

np.savetxt('/app/nanopore_signal.txt', data, fmt='%.6f')
EOF

    python3 /app/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
