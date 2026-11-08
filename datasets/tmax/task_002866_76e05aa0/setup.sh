#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest numpy h5py scipy

    # Create user and give sudo privileges
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Create setup script
    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np
import os

os.makedirs('/home/user/src', exist_ok=True)

N = 10
M = 1024
np.random.seed(42)

# Create signals with a mix of noise and a period-3 signal (frequency M/3)
t = np.arange(M)
signals = np.zeros((N, M), dtype=np.float64)

for i in range(N):
    noise = np.random.randn(M) * 0.5
    # Add a period-3 like signal (typical in exons) with varying amplitude
    amp = np.random.uniform(0.5, 2.0)
    periodic = amp * np.cos(2 * np.pi * (t / 3.0))
    signals[i] = noise + periodic

with h5py.File('/home/user/sequences.h5', 'w') as f:
    f.create_dataset('/dna_signals', data=signals, dtype='float64')
EOF

    # Run setup script
    python3 /tmp/setup_data.py

    # Create verify script
    cat << 'EOF' > /tmp/verify.py
import h5py
import numpy as np
from scipy.fft import fft
import sys

def verify():
    try:
        # Load input data to compute expected
        with h5py.File('/home/user/sequences.h5', 'r') as f:
            signals = f['/dna_signals'][:]

        N, M = signals.shape

        # Compute expected magnitude spectra
        mag_spectra = np.zeros_like(signals)
        for i in range(N):
            mag_spectra[i] = np.abs(fft(signals[i]))

        # SVD
        U, S, Vh = np.linalg.svd(mag_spectra, full_matrices=False)
        expected_s = S
        expected_v1 = Vh[0, :]

        # Load agent results
        with h5py.File('/home/user/results.h5', 'r') as f:
            agent_s = f['/singular_values'][:]
            agent_v1 = f['/principal_spectrum'][:]

        # Check singular values
        if not np.allclose(expected_s, agent_s, rtol=1e-3, atol=1e-3):
            print("Singular values mismatch")
            sys.exit(1)

        # Check principal spectrum (allow sign flip, as SVD sign is arbitrary)
        sign_flip = 1.0
        if np.sign(agent_v1[0]) != np.sign(expected_v1[0]) and agent_v1[0] != 0:
            sign_flip = -1.0

        if not np.allclose(expected_v1, agent_v1 * sign_flip, rtol=1e-3, atol=1e-3):
            print("Principal spectrum mismatch")
            sys.exit(1)

        print("Verification passed!")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    verify()
EOF

    chmod -R 777 /home/user
