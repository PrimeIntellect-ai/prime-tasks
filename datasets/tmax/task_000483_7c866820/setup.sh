#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import binascii

data = [
    # Device 1: utf-8 encoded, clean series with a gap
    ("2023-01-01T00:00:00Z", "Device_A".encode('utf-8').hex(), 10.5),
    ("2023-01-01T01:00:00Z", "Device_A".encode('utf-8').hex(), 11.0),
    ("2023-01-01T01:00:00Z", "Device_A".encode('utf-8').hex(), 11.0), # Duplicate
    ("2023-01-01T03:00:00Z", "Device_A".encode('utf-8').hex(), 15.0), # Gap at 02:00
    ("2023-01-01T04:00:00Z", "Device_A".encode('utf-8').hex(), 105.0), # Anomaly

    # Device 2: latin-1 encoded
    ("2023-01-01T00:00:00Z", "Dévice_B".encode('latin-1').hex(), 40.0),
    ("2023-01-01T01:00:00Z", "Dévice_B".encode('latin-1').hex(), 42.0),
    ("2023-01-01T02:00:00Z", "Dévice_B".encode('latin-1').hex(), 150.0), # Anomaly
    ("2023-01-01T03:00:00Z", "Dévice_B".encode('latin-1').hex(), 45.0),
]

df = pd.DataFrame(data, columns=["timestamp", "device_hex", "value"])
df.to_csv("/home/user/dirty_telemetry.csv", index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
