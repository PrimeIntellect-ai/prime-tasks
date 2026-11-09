#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import csv
import math

with open('/home/user/sensor_data_wide.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    header = ['sensor_id'] + [f't_{i}' for i in range(100)]
    writer.writerow(header)
    for s in range(1, 11): # 10 sensors
        row = [f'S{s:03d}']
        for t in range(100):
            # Generate missing values
            if 20 <= t <= 25 or t == 50 or 80 <= t <= 85:
                row.append('NaN')
            else:
                val = math.sin(t * 0.1) * s
                row.append(f"{val:.4f}")
        writer.writerow(row)
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
