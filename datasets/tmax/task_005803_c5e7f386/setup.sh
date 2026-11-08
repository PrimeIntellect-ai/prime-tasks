#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_samples.py
import numpy as np
np.random.seed(42)
samples = np.random.normal(0, 1.2, 10000)
np.savetxt('/home/user/samples.csv', samples, delimiter=',')
EOF

    python3 /tmp/generate_samples.py

    chmod -R 777 /home/user
