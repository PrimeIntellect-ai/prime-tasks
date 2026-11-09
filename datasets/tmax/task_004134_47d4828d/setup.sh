#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    # Create directories
    mkdir -p /home/user/data

    # Generate data
    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
np.random.seed(123)
X = np.random.uniform(0.1, 1.0, size=(100, 10))
np.savetxt('/home/user/data/vectors.csv', X, delimiter=',')
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
