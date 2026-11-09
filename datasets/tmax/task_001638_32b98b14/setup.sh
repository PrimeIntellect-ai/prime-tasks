#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv

raw_data = [
    [100, "S1", 3.0, 4.0, 20.0],
    [101, "S2", 5.0, 12.0, 25.0],
    [102, "S1", 3.0, 4.0, 20.0],
    [103, "S1", 3.0, 4.0, 21.0],
    [104, "S1", 3.0, 4.0, 22.0],
    [105, "S2", 5.0, 12.0, 26.0],
    [106, "S1", 3.0, 4.0, 23.0],
    [107, "S1", 3.0, 4.0, 35.0],
    [108, "S2", 5.0, 12.0, 26.0],
    [109, "S2", 5.0, 12.0, 27.0],
    [110, "S2", 5.0, 12.0, 45.0],
]

with open("/home/user/sensors_raw.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Timestamp", "SensorID", "CoordX", "CoordY", "Temperature"])
    for row in raw_data:
        writer.writerow(row)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
