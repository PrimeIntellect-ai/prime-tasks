#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
np.random.seed(42)
# Create a 1000x20 matrix with some correlated features
base = np.random.randn(1000, 5)
transformation = np.random.randn(5, 20)
data = base @ transformation + np.random.randn(1000, 20) * 0.5
np.savetxt('/home/user/data/matrix.csv', data, delimiter=',')
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
