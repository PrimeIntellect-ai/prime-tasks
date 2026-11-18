#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.txt
[2023-10-01 10:00:15] DEVICE_A TEMP=22.5
[2023-10-01 10:00:45] DEVICE_B TEMP=21.0
[2023-10-01 10:01:10] DEVICE_A TEMP=22.7
[2023-10-01 10:01:55] DEVICE_A TEMP=22.8
[2023-10-01 10:02:50] DEVICE_A TEMP=23.0
[2023-10-01 10:05:05] DEVICE_A TEMP=23.5
[2023-10-01 10:05:59] DEVICE_C TEMP=19.9
[2023-10-01 10:06:00] DEVICE_A TEMP=23.6
[2023-10-01 10:09:15] DEVICE_A TEMP=24.0
[2023-10-01 10:10:01] DEVICE_A TEMP=24.1
EOF

    chmod -R 777 /home/user
