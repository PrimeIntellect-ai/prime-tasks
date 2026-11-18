#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_baseline.py
import math
with open("/home/user/baseline.txt", "w") as f:
    for i in range(100):
        # Create a mock spectral peak
        val = math.exp(-((i - 50)**2) / 200.0) + 0.1
        f.write(f"{val:.6f}\n")
EOF
    python3 /home/user/generate_baseline.py

    chmod -R 777 /home/user
