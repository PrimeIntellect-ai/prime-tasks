#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ msmtp gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_sensors.log
[INFO] 2023-10-24 10:00:00 Booting up...
[DATA] 2023-10-24 10:01:00 | val=42.1
[DATA] 2023-10-24 10:02:00 | val=88.7
[ERROR] 2023-10-24 10:02:15 Connection lost
[DATA] 2023-10-24 10:03:00 | val=85.5
[DATA] 2023-10-24 10:04:00 | val=90.00
[DEBUG] 2023-10-24 10:04:30 Recalibrating
[DATA] 2023-10-24 10:05:00 | val=102.34
EOF

    chmod -R 777 /home/user
