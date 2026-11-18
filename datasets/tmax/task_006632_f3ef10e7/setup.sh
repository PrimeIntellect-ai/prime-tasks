#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import csv

np.random.seed(42)
t = np.arange(0, 100, 0.1) # 10 Hz sampling for 100 seconds (1000 samples)

# V1: Base 50ms + 1.5 Hz periodic spike (amplitude 15) + normal noise (std 5)
v1_lat = 50 + 15 * np.sin(2 * np.pi * 1.5 * t) + np.random.normal(0, 5, len(t))
# V2: Base 45ms + normal noise (std 5), no periodic spike
v2_lat = 45 + np.random.normal(0, 5, len(t))

def write_csv(filename, time_arr, lat_arr):
    with open(filename, 'w') as f:
        f.write("timestamp,latency_ms\n")
        for i in range(len(time_arr)):
            # Inject TIMEOUT randomly ~5% of the time
            if np.random.rand() < 0.05:
                f.write(f"{time_arr[i]:.1f},TIMEOUT\n")
            else:
                f.write(f"{time_arr[i]:.1f},{lat_arr[i]:.4f}\n")

write_csv('/home/user/v1_latency.csv', t, v1_lat)
write_csv('/home/user/v2_latency.csv', t, v2_lat)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
