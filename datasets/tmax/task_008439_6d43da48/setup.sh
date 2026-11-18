#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/evaluate_fit.py
#!/usr/bin/env python3
import sys
import time

if len(sys.argv) != 3:
    print("Usage: evaluate_fit.py <center_freq> <bandwidth>")
    sys.exit(1)

cf = float(sys.argv[1])
bw = float(sys.argv[2])

# True hidden minimum is at center_freq=11.7, bandwidth=1.9
# MSE = (cf - 11.7)^2 + (bw - 1.9)^2 + 0.1234
mse = (cf - 11.7)**2 + (bw - 1.9)**2 + 0.1234

# Artificial delay to encourage parallelization
time.sleep(0.05)

print(f"{mse:.4f}")
EOF

    chmod +x /home/user/evaluate_fit.py
    chmod -R 777 /home/user
