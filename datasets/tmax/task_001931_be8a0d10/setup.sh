#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import math

with open('/home/user/spectra.csv', 'w') as f:
    f.write("x,intensity\n")
    for x in range(100):
        # Deterministic function simulating a spatial spectral signal
        intensity = 10.0 + 5.0 * math.sin(x / 10.0) + 2.0 * math.cos(x / 3.0)
        f.write(f"{x},{intensity:.6f}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
