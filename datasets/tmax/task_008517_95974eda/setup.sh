#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

# Generate signals (low frequency + high frequency noise)
t = np.linspace(0, 100, 1000)
signals = np.zeros((1000, 50))
for i in range(50):
    # Base signal
    signals[:, i] = np.sin(t * np.random.uniform(0.1, 0.5) + np.random.uniform(0, 2*np.pi))
    # High freq noise
    signals[:, i] += 0.5 * np.random.randn(1000) + 0.2 * np.sin(t * 5.0)

np.savetxt('/home/user/signals.csv', signals, delimiter=',')

# True weights for the first 3 components of the filtered data
true_weights = np.array([2.5, -1.2, 0.8])

# Compute the target directly from the expected process to ensure ground truth matches exactly
X = signals.copy()
freqs = np.fft.fftfreq(1000)
for i in range(50):
    F_c = np.fft.fft(X[:, i])
    F_c[np.abs(freqs) > 0.1] = 0
    X[:, i] = np.real(np.fft.ifft(F_c))

U, S, Vt = np.linalg.svd(X, full_matrices=False)
F = U[:, :3] * S[:3]

# Generate target with some noise
target = F @ true_weights + 0.1 * np.random.randn(1000)
np.savetxt('/home/user/target.csv', target, delimiter=',')

# Solve to get exact expected output
w, _, _, _ = np.linalg.lstsq(F, target, rcond=None)
expected_output = f"{w[0]:.6f},{w[1]:.6f},{w[2]:.6f}\n"

with open('/tmp/expected_weights.txt', 'w') as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py

    chown -R user:user /home/user/signals.csv /home/user/target.csv
    chmod -R 777 /home/user
