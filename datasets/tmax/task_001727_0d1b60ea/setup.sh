#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar cron
    pip3 install pytest

    # Install Go
    wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
    rm go1.21.0.linux-amd64.tar.gz

    # Create user
    useradd -m -s /bin/bash user || true

    # Create raw_sensors.csv with ISO-8859-1 encoding
    cat << 'EOF' > /tmp/create_data.py
import os

os.makedirs('/home/user', exist_ok=True)
csv_content = b"""timestamp,sensor_name,temperature
2023-10-01 10:05:00,Caf\xe9_Front,22.5
2023-10-01 10:15:00,Caf\xe9_Front,23.0
2023-10-01 11:05:00,Caf\xe9_Back,160.0
2023-10-01 11:25:00,Caf\xe9_Back,24.1
2023-10-01 11:35:00,Caf\xe9_Back,24.5
2023-10-01 12:05:00,Caf\xe9_Ext,-60.0
2023-10-01 12:55:00,Caf\xe9_Ext,-10.0
"""
with open('/home/user/raw_sensors.csv', 'wb') as f:
    f.write(csv_content)
EOF
    python3 /tmp/create_data.py
    rm /tmp/create_data.py

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
