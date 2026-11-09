#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    # Create user
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate the initial signal data
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(123)
time = np.linspace(0, 100, 2000) # 0 to 100 ms, 2000 points => 0.05 ms spacing => max freq 10 kHz
# True parameters
true_a = 15.0
true_c = 0.5
true_mu = 45.0
true_b = 5.0

# Base signal
signal = true_a * np.exp(-true_c * (time - true_mu)**2) + true_b

# Add high frequency noise (e.g., 2.0 kHz and 3.5 kHz)
noise_hf = 3.0 * np.sin(2 * np.pi * 2.0 * time) + 2.0 * np.cos(2 * np.pi * 3.5 * time)

# Add random white noise
noise_white = np.random.normal(0, 0.5, size=len(time))

total_signal = signal + noise_hf + noise_white

df = pd.DataFrame({'time': time, 'current': total_signal})
os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/signal_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
