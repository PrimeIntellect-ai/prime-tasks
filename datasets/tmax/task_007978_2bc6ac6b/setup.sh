#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk sed
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_signal.py
import math
with open("/home/user/raw_signal.tsv", "w") as f:
    for i in range(50):
        # Deterministic pseudo-noisy signal
        val = math.sin(i / 5.0) + 0.5 * math.cos(i) + (i % 3) * 0.1
        f.write(f"{val:.6f}\n")
EOF
    python3 /home/user/generate_signal.py
    rm /home/user/generate_signal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
