#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transform_step.py
import os
import time
import numpy as np

# Simulate an ETL transformation workload
np.random.seed(42)
A = np.random.rand(800, 800)
B = np.random.rand(800, 800)

start = time.time()
C = np.dot(A, B)
end = time.time()

print(end - start)
EOF
    chmod +x /home/user/transform_step.py

    chmod -R 777 /home/user
