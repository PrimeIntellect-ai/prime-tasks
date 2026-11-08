#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    cat << 'EOF' > /home/user/setup_data.py
import csv
import os

os.makedirs('/home/user/raw_data', exist_ok=True)

data_1 = [
    ["sensor_id","timestamp","temperature","humidity","status"],
    ["SN-1234","2023-10-01T10:00:00Z","22.5","45.0","ACTIVE"],
    ["SN-1234","2023-10-01T10:05:00Z","100.0","45.0","ACTIVE"],
    ["S-123","2023-10-01T10:10:00Z","22.5","45.0","BROKEN"],
    ["SN-9999","2023-10-01T10:15:00Z","-45.0","105.0","MAINTENANCE"],
    ["SN-0001","2023-10-01T10:20:00Z","0.0","0.0","OFFLINE"]
]

data_2 = [
    ["sensor_id","timestamp","temperature","humidity","status"],
    ["SN-4321","2023-10-02T10:00:00Z","abc","45.0","ACTIVE"],
    ["SN-4321","2023-10-02 10:05:00Z","20.0","45.0","ACTIVE"],
    ["SN-5555","2023-10-02T10:10:00Z","85.0","100.0","MAINTENANCE"]
]

with open('/home/user/raw_data/file1.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data_1)

with open('/home/user/raw_data/file2.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data_2)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
