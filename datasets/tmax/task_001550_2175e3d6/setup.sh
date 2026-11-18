#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os

raw_data = [
    # Valid row, requires no clamping
    "1,2023-10-01T12:00:00," + ",".join([str(float(i)) for i in range(1, 31)]),
    # Invalid row: wrong number of columns (31 total)
    "2,2023-10-01T12:00:01," + ",".join(["1.0"] * 29),
    # Invalid row: non-integer ID
    "A,2023-10-01T12:00:02," + ",".join(["1.0"] * 30),
    # Invalid row: non-float sensor reading
    "3,2023-10-01T12:00:03," + ",".join(["1.0"] * 29) + ",bad",
    # Valid row, requires clamping on dim2 (>100) and dim3 (<-100)
    "4,2023-10-01T12:00:04," + ",".join(["10.0"] * 10) + "," + ",".join(["150.0"] * 10) + "," + ",".join(["-200.0"] * 10),
    # Valid row, mixed values
    "5,2023-10-01T12:00:05," + ",".join(["0.5", "1.5", "2.5", "3.5", "4.5", "5.5", "6.5", "7.5", "8.5", "9.5"]) + "," + ",".join(["-10", "20", "5", "8", "99", "12", "1", "-5", "4", "0"]) + "," + ",".join(["10", "20", "5", "8", "99", "12", "1", "-5", "4", "0"])
]

with open("/home/user/raw_sensors.csv", "w") as f:
    for line in raw_data:
        f.write(line + "\n")
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
