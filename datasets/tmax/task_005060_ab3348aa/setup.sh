#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest pandas numpy

    mkdir -p /app/data/sample_clean
    mkdir -p /app/data/sample_evil
    mkdir -p /app/data/hidden_clean
    mkdir -p /app/data/hidden_evil

    # Generate the audio file
    espeak -w /app/operator_notes.wav "Maintenance window and ETL retries occurred between fourteen hundred and sixteen hundred hours."

    # Generate the datasets
    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

def generate_clean(filename):
    dates = pd.date_range('2023-01-01 00:00:00', '2023-01-01 23:59:00', freq='T')
    df = pd.DataFrame({'timestamp': dates})
    for i in range(1, 11):
        df[f'sensor{i}'] = np.sin(np.linspace(0, 10, len(dates))) * 10 + 20 + np.random.normal(0, 0.1, len(dates))
    df.to_csv(filename, index=False)

def generate_evil_jump(filename):
    dates = pd.date_range('2023-01-01 00:00:00', '2023-01-01 23:59:00', freq='T')
    df = pd.DataFrame({'timestamp': dates})
    for i in range(1, 11):
        base = np.sin(np.linspace(0, 10, len(dates))) * 10 + 20 + np.random.normal(0, 0.1, len(dates))
        base[500:] *= 1.6 # Jump > 50%
        df[f'sensor{i}'] = base
    df.to_csv(filename, index=False)

def generate_evil_dup(filename):
    dates = pd.date_range('2023-01-01 00:00:00', '2023-01-01 23:59:00', freq='T')
    df = pd.DataFrame({'timestamp': dates})
    for i in range(1, 11):
        df[f'sensor{i}'] = np.sin(np.linspace(0, 10, len(dates))) * 10 + 20 + np.random.normal(0, 0.1, len(dates))

    mask = (df['timestamp'].dt.hour >= 14) & (df['timestamp'].dt.hour < 16)
    dups = df[mask].sample(10)
    df = pd.concat([df, dups]).sort_values('timestamp')
    df.to_csv(filename, index=False)

for i in range(5):
    generate_clean(f'/app/data/sample_clean/clean_{i}.csv')
    if i % 2 == 0:
        generate_evil_jump(f'/app/data/sample_evil/evil_{i}.csv')
    else:
        generate_evil_dup(f'/app/data/sample_evil/evil_{i}.csv')

for i in range(20):
    generate_clean(f'/app/data/hidden_clean/clean_{i}.csv')
    if i % 2 == 0:
        generate_evil_jump(f'/app/data/hidden_evil/evil_{i}.csv')
    else:
        generate_evil_dup(f'/app/data/hidden_evil/evil_{i}.csv')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
