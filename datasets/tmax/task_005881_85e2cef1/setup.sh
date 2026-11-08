#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output
    mkdir -p /home/user/etl

    cat << 'EOF' > /tmp/setup_data.py
import os

sensor_a = "1600000000,10.5,Température\n1600000060,11.0,Température\n1600000120,12.5,Élevé\n1600000180,10.1,Normal\n"
with open('/home/user/data/sensor_a.csv', 'w', encoding='iso-8859-1') as f:
    f.write(sensor_a)

sensor_b = "1600000000,10.0,Normal\n1600000060,11.2,Normal\n1600000150,13.0,Anomalie\n1600000180,9.9,Normal\n"
with open('/home/user/data/sensor_b.csv', 'w', encoding='utf-16le') as f:
    f.write(sensor_b)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
