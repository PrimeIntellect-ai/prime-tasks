#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential
    pip3 install pytest numpy

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np
np.random.seed(42)
# Create a rank-5 matrix with some noise
U = np.random.randn(50, 5)
V = np.random.randn(5, 20)
R = U @ V + np.random.randn(50, 20) * 0.5
np.savetxt('/home/user/data/matrix.txt', R, fmt='%.6f', delimiter=' ')
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
