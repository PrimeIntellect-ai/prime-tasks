#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input

    cat << 'EOF' > /home/user/input/readings.tsv
2023-10-01T10:00:00Z	DEV_A	{"temperature": 22.0, "humidity": 45}
2023-10-01T10:01:00Z	DEV_A	{"temperature": 22.5, "humidity": 45}
2023-10-01T10:00:00Z	DEV_A	{"temperature": 22.0, "humidity": 45}
2023-10-01T10:02:00Z	DEV_A	{"temperature": 21.5, "humidity": 46}
2023-10-01T10:03:00Z	DEV_B	{"temperature": 15.0, "humidity": 50}
2023-10-01T10:03:00Z	DEV_A	{"temperature": 32.5, "humidity": 42}
2023-10-01T10:04:00Z	DEV_A	{"temperature": 33.0, "humidity": 40}
2023-10-01T10:04:00Z	DEV_B	{"temperature": 15.2, "humidity": 50}
2023-10-01T10:05:00Z	DEV_B	{"temperature": 14.8, "humidity": 51}
2023-10-01T10:06:00Z	DEV_B	{"temperature": 26.0, "humidity": 45}
2023-10-01T10:06:00Z	DEV_B	{"temperature": 26.0, "humidity": 45}
2023-10-01T10:07:00Z	DEV_C	{"temperature": 10.0, "humidity": 60}
2023-10-01T10:08:00Z	DEV_C	{"temperature": 10.5, "humidity": 60}
EOF

    chmod -R 777 /home/user
