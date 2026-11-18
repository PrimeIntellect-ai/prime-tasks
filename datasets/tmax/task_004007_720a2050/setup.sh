#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/models

    cat << 'EOF' > /home/user/models/ground_truth.py
import numpy as np

def compute_true(x: np.ndarray) -> np.ndarray:
    return np.exp(-x / 10.0) * np.sin(x) * np.cos(2 * x)
EOF

    cat << 'EOF' > /home/user/models/fast_approx.py
import numpy as np

def compute_approx(x: np.ndarray) -> np.ndarray:
    # Simulating a faster approximation by downcasting to float32 for computation
    x32 = x.astype(np.float32)
    result = np.exp(-x32 / 10.0) * np.sin(x32) * np.cos(2 * x32)
    return result.astype(np.float64)
EOF

    chmod +x /home/user/models/*.py
    chmod -R 777 /home/user
