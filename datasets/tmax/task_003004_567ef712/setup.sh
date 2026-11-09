#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo build-essential
    pip3 install pytest numpy pandas

    # Create user and configure sudo
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate reference.wav and CSV files
    python3 -c "
import wave
import struct
import numpy as np
import pandas as pd
import os

# Create minimal wav file
with wave.open('/app/reference.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframesraw(struct.pack('<h', 0) * 44100)

# Create clean CSVs (std <= 10.5)
for i in range(5):
    df_clean = pd.DataFrame({'time': np.linspace(0, 1, 100), 'amplitude': np.random.normal(0, 5, 100)})
    df_clean.to_csv(f'/app/corpus/clean/clean_{i}.csv', index=False)

# Create evil CSVs (std > 10.5)
for i in range(5):
    df_evil = pd.DataFrame({'time': np.linspace(0, 1, 100), 'amplitude': np.random.normal(0, 20, 100)})
    df_evil.to_csv(f'/app/corpus/evil/evil_{i}.csv', index=False)
"

    chmod -R 777 /app
    chmod -R 777 /home/user
