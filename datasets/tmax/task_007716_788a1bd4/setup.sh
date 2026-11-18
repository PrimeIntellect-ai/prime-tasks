#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/simulate.py
import numpy as np
import time

def compute_spectrum(x):
    res = np.zeros_like(x)
    for i in range(len(x)):
        val = 0.0
        for j in range(50):
            val += np.sin(x[i] * j) * np.exp(-((x[i] - j)/0.1)**2)
        res[i] = val
    return res

if __name__ == "__main__":
    start = time.time()
    x = np.linspace(0, 50, 10000)
    y = compute_spectrum(x)
    np.save('/home/user/output.npy', y)
    print(f"Time: {time.time() - start}")
EOF

    python3 /home/user/simulate.py
    mv /home/user/output.npy /home/user/reference.npy

    chmod -R 777 /home/user
