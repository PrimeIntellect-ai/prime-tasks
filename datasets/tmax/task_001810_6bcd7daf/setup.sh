#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    # Create the raw_data.csv file with cp1252 encoding
    cat << 'EOF' > /tmp/create_data.py
import os

data = [
    b"timestamp,comment,sensor_value",
    b"2023-10-01T10:00:00Z,  Temperature is \t ok!  ,45.5",
    b"2023-10-01T10:01:00Z,It\x92s getting hot   ,105.2",
    b"2023-10-01T10:02:00Z,  cooldown ,42.0",
    b"2023-10-01T10:03:00Z,   steady... ,44.5",
    b"2023-10-01T10:04:00Z,error reading,-5.0",
    b"2023-10-01T10:05:00Z,  all   good  ,46.0"
]

with open("/home/user/raw_data.csv", "wb") as f:
    f.write(b"\n".join(data))
EOF

    python3 /tmp/create_data.py
    rm /tmp/create_data.py

    chmod -R 777 /home/user
