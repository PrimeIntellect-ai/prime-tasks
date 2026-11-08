#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import random
import os

np.random.seed(42)
times = np.linspace(0, 1, 1000)
params = [
    (3.0, 2.0, 0.5),
    (5.0, 1.5, -0.2),
    (7.0, 3.0, 1.0),
    (9.0, 2.5, -0.8)
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/measurements.txt", "w") as f:
    f.write("sensor_id timestamp measurement\n")
    lines = []
    for sid, (freq, amp, phase) in enumerate(params):
        y = amp * np.sin(2 * np.pi * freq * times + phase) + np.random.normal(0, 0.01, len(times))
        for t, val in zip(times, y):
            lines.append(f"{sid} {t:.6f} {val:.6f}\n")

    random.shuffle(lines)
    for line in lines:
        f.write(line)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
