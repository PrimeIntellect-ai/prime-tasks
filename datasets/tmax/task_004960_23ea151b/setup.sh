#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

random.seed(42)

log_data = [
    "[2023-10-12 08:14:02] DEVICE_A12 - STATUS:200 - TIME:45ms - MSG:Payload delivered\n",
    "[2023-10-12 08:15:00] DEVICE_A12 - STATUS:500 - TIME:120ms - MSG:Timeout\n",
    "[2023-10-12 08:16:00] DEVICE_B99 - STATUS:200 - TIME:30ms - MSG:OK\n",
    "[2023-10-12 08:17:00] DEVICE_B99 - STATUS:201 - TIME:25ms - MSG:Created\n",
    "[2023-10-12 08:18:00] DEVICE_B99 - STATUS:404 - TIME:55ms - MSG:Not Found\n",
    "[2023-10-12 08:19:00] DEVICE_C01 - STATUS:200 - TIME:10ms - MSG:Fast\n",
    # Invalid entries
    "[2023-10-12 08:20:00] DEV_X - STATUS:200 - TIME:10ms - MSG:Bad device ID\n",
    "[2023-10-12 08:21:00] DEVICE_A12 - STATUS:OK - TIME:45ms - MSG:Bad status\n",
    "[2023-10-12 08:22:00] DEVICE_A12 - STATUS:200 - TIME:-5ms - MSG:Negative time\n",
    "Completely corrupted log line here\n",
    "[2023-10-12 08:23:00] DEVICE_A12 - STATUS:200 - TIME:40ms - MSG:Tied time 1\n",
    "[2023-10-12 08:24:00] DEVICE_A12 - STATUS:200 - TIME:40ms - MSG:Tied time 2\n"
]

with open("/home/user/raw_logs.txt", "w") as f:
    f.writelines(log_data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
