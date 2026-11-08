#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/sensor_data
    mkdir -p /home/user/remote_sync

    # Generate deterministic binary data
    cat << 'EOF' > /tmp/generate_data.py
import struct
import os

os.makedirs('/home/user/sensor_data', exist_ok=True)

# Generate 10 files
for i in range(10):
    with open(f'/home/user/sensor_data/data_{i}.bin', 'wb') as f:
        # 5 sensors, specific deterministic values based on file index and sensor id
        for sensor_id in range(1, 6):
            # value = sensor_id * 10 + i
            val = float(sensor_id * 10 + i)
            f.write(struct.pack('<id', sensor_id, val))
EOF
    python3 /tmp/generate_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
