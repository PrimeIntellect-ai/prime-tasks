#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the setup script for generating the initial sensor_data.csv
    cat << 'EOF' > /tmp/setup.py
import csv

data = [
    # Minute 00: multiple readings (avg = 20.50)
    ("2023-10-01T00:00:15Z", "dev_42", 20.0),
    ("2023-10-01T00:00:45Z", "dev_42", 21.0),
    # Noise from other device
    ("2023-10-01T00:00:50Z", "dev_99", 100.0),

    # Minute 03: Gap of 2 minutes (01, 02). Should be filled with 20.50. Actual min 03 reading: 22.0
    ("2023-10-01T00:03:10Z", "dev_42", 22.0),

    # Minute 09: Gap of 5 minutes (04, 05, 06, 07, 08). Should be filled with 22.00. Actual min 09 reading: 23.0
    ("2023-10-01T00:09:05Z", "dev_42", 23.0),

    # Minute 16: Gap of 6 minutes (10, 11, 12, 13, 14, 15). Should NOT be filled. Actual min 16 reading: 25.0
    ("2023-10-01T00:16:20Z", "dev_42", 25.0),

    # Out of order timestamp but same minute 16 (avg = 25.50)
    ("2023-10-01T00:16:10Z", "dev_42", 26.0)
]

with open('/home/user/sensor_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "device_id", "temperature"])
    for row in data:
        writer.writerow(row)
EOF

    # Run the setup script to generate the data
    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Set permissions
    chmod -R 777 /home/user
