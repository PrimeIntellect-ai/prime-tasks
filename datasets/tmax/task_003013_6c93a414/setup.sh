#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import scipy.stats as stats
import csv
import json
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Generate Signal Data
fs = 1024
t = np.arange(1024) / fs
# Dominant frequencies: 50 Hz and 120 Hz
power = 3.0 * np.sin(2 * np.pi * 50 * t) + 2.0 * np.cos(2 * np.pi * 120 * t) 
np.random.seed(42)
power += np.random.normal(0, 0.5, 1024) # Add noise

with open('/home/user/cpu_signal.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'power'])
    for i in range(1024):
        writer.writerow([t[i], power[i]])

# 2. Generate Latency Data
np.random.seed(42)
latencies = np.random.lognormal(mean=3.0, sigma=0.5, size=5000)

with open('/home/user/latency_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['request_id', 'latency_ms'])
    for i in range(5000):
        writer.writerow([i+1, latencies[i]])

# Ground truth computation:
# FFT
fft_vals = np.fft.fft(power)
fft_freqs = np.fft.fftfreq(1024, 1/fs)
pos_mask = fft_freqs > 0
pos_freqs = fft_freqs[pos_mask]
pos_mags = np.abs(fft_vals)[pos_mask]
sorted_indices = np.argsort(pos_mags)[::-1]
dom_freqs = [pos_freqs[sorted_indices[0]], pos_freqs[sorted_indices[1]]] # Should be [50.0, 120.0]

# KDE & p99
p99 = np.percentile(latencies, 99)
kde = stats.gaussian_kde(latencies)
grid = np.linspace(0, 200, 2000)
kde_vals = kde(grid)
kde_peak = grid[np.argmax(kde_vals)]

# Convergence
convergence_n = -1
for n in range(2, 5001):
    sample = latencies[:n]
    sem = np.std(sample, ddof=1) / np.sqrt(n)
    if sem < 0.20:
        convergence_n = n
        break

truth = {
    "dominant_frequencies": [round(dom_freqs[0], 2), round(dom_freqs[1], 2)],
    "latency_kde_peak": round(kde_peak, 2),
    "latency_p99": round(p99, 2),
    "convergence_n": convergence_n
}

with open('/home/user/.truth.json', 'w') as f:
    json.dump(truth, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
