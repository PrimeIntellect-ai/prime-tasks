#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

def generate_data():
    np.random.seed(42)
    fs = 200.0
    t = np.arange(0, 100, 1/fs)
    # True signal is Hypothesis A: 10, 25, 50 Hz
    signal = 2.0 * np.sin(2 * np.pi * 10 * t) + \
             1.5 * np.sin(2 * np.pi * 25 * t) + \
             1.0 * np.sin(2 * np.pi * 50 * t)

    # Add significant white noise
    noise = np.random.normal(0, 5.0, len(t))
    amplitude = signal + noise

    df = pd.DataFrame({'time': t, 'amplitude': amplitude})
    df.to_csv('/home/user/spectroscopy_data.csv', index=False)

if __name__ == "__main__":
    generate_data()
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
