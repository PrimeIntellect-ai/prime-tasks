#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy setuptools

    mkdir -p /app/fast-stat-profiler-1.0
    cat << 'EOF' > /app/fast-stat-profiler-1.0/setup.py
from setuptools import setup
import os

if os.environ.get("ALLOW_PROFILER_BUILD") != "1":
    raise RuntimeError("Build not allowed")

setup(
    name="fast-stat-profiler",
    version="1.0",
    packages=["fast_stat_profiler"],
)
EOF

    cat << 'EOF' > /app/fast-stat-profiler-1.0/Makefile
install:
	python setup.py install --user
EOF

    mkdir -p /app/fast-stat-profiler-1.0/fast_stat_profiler
    cat << 'EOF' > /app/fast-stat-profiler-1.0/fast_stat_profiler/__init__.py
import numpy as np

def clean_latency(data):
    # Convert to float array, replace NaNs with 0.0, replace negatives with 0.0
    arr = np.array(data, dtype=float)
    arr[np.isnan(arr)] = 0.0
    arr[arr < 0] = 0.0
    return arr
EOF

    mkdir -p /oracle
    cat << 'EOF' > /oracle/analyze_jitter_oracle.py
import sys
import numpy as np
import fast_stat_profiler

def main():
    lines = sys.stdin.read().strip().split('\n')
    if not lines or lines == ['']:
        return
    latencies = []
    for line in lines:
        try:
            parts = line.split(',')
            latencies.append(float(parts[1]))
        except:
            pass

    cleaned = fast_stat_profiler.clean_latency(latencies)
    fft_vals = np.fft.fft(cleaned)
    mags = np.abs(fft_vals)

    # Ignore DC component
    mags[0] = -1.0

    # Sort by magnitude descending, then index ascending
    # We can do this by creating a list of tuples
    mag_idx = [(-mags[i], i) for i in range(1, len(mags))]
    mag_idx.sort()

    for i in range(min(3, len(mag_idx))):
        mag = -mag_idx[i][0]
        idx = mag_idx[i][1]
        print(f"Idx: {idx}, Mag: {mag:.4f}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /oracle/analyze_jitter_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
