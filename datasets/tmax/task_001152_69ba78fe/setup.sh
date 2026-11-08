#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy golang build-essential make
    pip3 install pytest

    mkdir -p /app/vendor/telemetry-parser

    cat << 'EOF' > /app/vendor/telemetry-parser/go.mod
module telemetry

go 1.18
EOF

    cat << 'EOF' > /app/vendor/telemetry-parser/stats.go
package telemetry

// #include <math.h>
import "C"

func FastLog(x float64) float64 {
    return float64(C.log(C.double(x)))
}
EOF

    cat << 'EOF' > /app/vendor/telemetry-parser/Makefile
export CGO_ENABLED=0
build:
	go build -o bin/telemetry ./...
EOF

    cat << 'EOF' > /tmp/generate_corpora.py
import numpy as np
import os

os.makedirs('/home/user/corpora/clean', exist_ok=True)
os.makedirs('/home/user/corpora/evil', exist_ok=True)

np.random.seed(42)
N = 1024 # power of 2 for easy FFT
t = np.arange(N)

for i in range(50):
    # Clean: log-normal noise
    clean_latency = np.random.lognormal(mean=2.0, sigma=0.5, size=N)
    with open(f'/home/user/corpora/clean/trace_{i}.csv', 'w') as f:
        f.write("timestamp_ms,latency_ms\n")
        for ts, lat in zip(t, clean_latency):
            f.write(f"{ts},{lat:.4f}\n")

    # Evil: log-normal noise + strong 50Hz sine wave artifact
    noise = np.random.lognormal(mean=2.0, sigma=0.5, size=N)
    # Frequency = 50 cycles per N samples
    sine_wave = 15.0 * np.sin(2 * np.pi * 50 * t / N)
    evil_latency = noise + sine_wave + 20.0 # Shifted to keep > 0
    with open(f'/home/user/corpora/evil/trace_{i}.csv', 'w') as f:
        f.write("timestamp_ms,latency_ms\n")
        for ts, lat in zip(t, evil_latency):
            f.write(f"{ts},{lat:.4f}\n")
EOF

    python3 /tmp/generate_corpora.py
    rm /tmp/generate_corpora.py

    mkdir -p /home/user/prof_classifier
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
