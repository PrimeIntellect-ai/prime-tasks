#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import os

data = [
    (1.0, 3.0),
    (2.0, 5.0),
    (-999.0, 4.0),   # Missing X
    (3.0, 7.0),
    (4.0, 9.0),
    (5.0, 88.0),     # Outlier Y
    (5.0, 11.0),
    (6.0, 13.0),
    (7.0, 15.0),
    (8.0, 17.0),
    (200.0, 400.0),  # Outlier X and Y
    (9.0, 19.0),
    (10.0, 21.0)
]

with open("/home/user/sensor_data.csv", "w") as f:
    for x, y in data:
        f.write(f"{x},{y}\n")
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
