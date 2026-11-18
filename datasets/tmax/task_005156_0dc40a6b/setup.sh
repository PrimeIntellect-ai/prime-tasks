#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sys

raw_logs = [
    "2023-10-01 10:00:05 | U100 | Initial startup sequence\x80\x81",
    "2023-10-01 10:00:30 | U100 | Initial startup sequence\x82", # duplicate after clean
    "2023-10-01 10:00:55 | U200 | Late entry for min 00",
    "2023-10-01 10:01:10 | U300 | Valid entry for min 01 \xff\xfe test",
    "2023-10-01 10:02:45 | U300 | Valid entry for min 01 test", # duplicate after clean
    # Min 02 is empty
    "2023-10-01 10:03:15 | U400 | Checking connection...",
    "2023-10-01 10:04:01 | U500 | Ping received",
    "2023-10-01 10:04:02 | U500 | Ping received", # duplicate
    "2023-10-01 10:04:59 | U600 | Another message in min 04",
    # Min 05 empty
    # Min 06 empty
    "2023-10-01 10:07:30 | U700 | Sync\x01\x02ing data",
    "2023-10-01 10:08:12 | U800 | Normal operations",
    "2023-10-01 10:09:05 | U900 | Warning: High CPU",
    "2023-10-01 10:10:00 | U900 | Warning: High CPU", # duplicate
    "2023-10-01 10:11:59 | U100 | Restarting service",
    # Min 12 empty
    "2023-10-01 10:13:05 | U200 | Database connected",
    "2023-10-01 10:14:20 | U300 | Closing connections",
    "2023-10-01 10:15:05 | U999 | Should be ignored, out of bounds",
    "2023-10-01 10:15:00 | U400 | Final shutdown" # wait, 10:15:00 is within bounds
]

with open("/home/user/raw_logs.txt", "w", encoding="latin1") as f:
    for log in raw_logs:
        f.write(log + "\n")
EOF
    python3 /home/user/setup.py

    chmod -R 777 /home/user
