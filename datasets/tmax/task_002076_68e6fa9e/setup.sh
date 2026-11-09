#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base
    pip3 install pytest numpy scipy

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np

# Generate stable pseudo-random data
np.random.seed(42)
# shape = 2.5, scale = 1.5
data = np.random.gamma(2.5, 1.5, 1000)

with open("/home/user/data/observations.txt", "w") as f:
    for val in data:
        f.write(f"{val}\n")
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
