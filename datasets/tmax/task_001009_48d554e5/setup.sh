#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter nbconvert matplotlib numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
np.random.seed(1)
data_a = np.random.exponential(scale=45.0, size=500)
data_b = np.random.exponential(scale=41.5, size=500)
np.savetxt('/home/user/latency_a.txt', data_a, fmt='%.4f')
np.savetxt('/home/user/latency_b.txt', data_b, fmt='%.4f')
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
