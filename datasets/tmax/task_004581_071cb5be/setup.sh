#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
np.random.seed(42)
t = np.linspace(0, 1, 1024, endpoint=False)
data = np.zeros((100, 1024))
for i in range(100):
    freq = np.random.normal(50, 5)
    data[i] = np.sin(2 * np.pi * freq * t) + np.random.normal(0, 0.5, 1024)
np.save('/home/user/sensor_data.npy', data)
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
