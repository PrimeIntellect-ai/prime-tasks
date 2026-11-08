#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import math
import random

random.seed(42)

A_true = 4.2
mu_true = 1.3
sigma = 1.0
noise_std = 0.5

with open('/home/user/spectrum.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['wavelength', 'intensity'])
    for i in range(101):
        x = -5.0 + i * 0.1
        clean_intensity = A_true * math.exp(-((x - mu_true)**2) / (2 * sigma**2))
        noise = random.gauss(0, noise_std)
        intensity = clean_intensity + noise
        writer.writerow([round(x, 2), round(intensity, 4)])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
