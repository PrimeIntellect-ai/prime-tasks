#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,temperature,humidity
2023-10-01T00:15:00,20.0,50.0
2023-10-01T00:45:00,22.0,52.0
2023-10-01T02:30:00,24.0,56.0
2023-10-01T03:10:00,25.0,58.0
2023-10-01T03:50:00,27.0,60.0
2023-10-02T22:00:00,18.0,45.0
2023-10-02T23:55:00,19.0,46.0
EOF

    chown user:user /home/user/sensor_data.csv
    chmod -R 777 /home/user
