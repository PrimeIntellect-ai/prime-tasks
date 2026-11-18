#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

# Create raw data
np.random.seed(42)
t = np.linspace(0, 10, 1000)
amp = 2.5 * np.sin(2 * np.pi * 1.5 * t) + 1.2 * np.sin(2 * np.pi * 5.0 * t) + np.random.normal(0, 0.2, 1000)

# Introduce NaNs to test ETL
amp[50] = np.nan
amp[250] = np.nan
amp[899] = np.nan

df = pd.DataFrame({'time': t, 'amplitude': amp})
df.to_csv('/home/user/raw_waves.csv', index=False)

# Create skeleton script
skeleton_code = """import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import time
import json

# TODO: Load data, drop NaNs, and save to cleaned_waves.csv

# TODO: Benchmark numpy.fft.fft on the amplitude column and save to benchmark.txt

# TODO: Test Parseval's theorem and save to accuracy.json

# TODO: Plot absolute FFT and save to spectrum.png
plt.plot([1, 2, 3]) # Placeholder
plt.savefig('/home/user/spectrum.png')
"""
with open('/home/user/process_waves.py', 'w') as f:
    f.write(skeleton_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
