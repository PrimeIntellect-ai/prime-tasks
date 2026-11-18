#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/temperature.csv
timestamp,temperature
2023-10-01T10:00:15Z,20.0
2023-10-01T10:00:45Z,22.0
2023-10-01T10:01:30Z,21.0
2023-10-01T10:03:10Z,24.0
2023-10-01T10:05:05Z,25.0
2023-10-01T10:06:59Z,26.0
EOF

    cat << 'EOF' > /home/user/data/pressure.csv
timestamp,pressure
2023-10-01T10:00:05Z,100.0
2023-10-01T10:02:00Z,102.0
2023-10-01T10:04:00Z,106.0
2023-10-01T10:06:00Z,104.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
