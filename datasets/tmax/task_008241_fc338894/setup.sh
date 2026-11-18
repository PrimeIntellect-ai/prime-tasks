#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate initial state data
    python3 -c "
import os
import numpy as np

os.makedirs('/home/user/sensor_data', exist_ok=True)

np.random.seed(42)
for i in range(20):
    filename = f'/home/user/sensor_data/data_{i:02d}.csv'

    # Generate 256 points
    t = np.arange(256)

    # Decide if singular (massive DC)
    is_singular = i in [3, 7, 14, 18]

    dc_offset = 2000.0 if is_singular else np.random.uniform(-5.0, 5.0)
    dom_freq = np.random.randint(5, 50)

    # Signal = DC + Sine + Noise
    signal = dc_offset + 10.0 * np.sin(2 * np.pi * dom_freq * t / 256) + np.random.normal(0, 0.5, 256)

    with open(filename, 'w') as f:
        f.write('timestamp,value\n')
        f.write('# this is a comment\n')
        f.write('\n')
        for idx, val in enumerate(signal):
            f.write(f'{idx},{val:.4f}\n')
            if idx == 100:
                f.write('# mid-file comment\n\n')
"

    # Set permissions
    chmod -R 777 /home/user
