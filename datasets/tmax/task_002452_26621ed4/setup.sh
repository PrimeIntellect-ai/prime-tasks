#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.log
LOG_START [2023-11-01T08:00:00] - sensor_alpha reported temp: 20.0
LOG_START [2023-11-01T08:00:00] - sensor_beta reported temp: 15.5
LOG_START [2023-11-01T08:00:00] - sensor_alpha reported temp: 20.0
LOG_START [2023-11-01T08:15:00] - sensor_alpha reported temp: ERROR
LOG_START [2023-11-01T08:15:00] - sensor_beta reported temp: 16.0
LOG_START [2023-11-01T08:30:00] - sensor_alpha reported temp: 25.0
LOG_START [2023-11-01T08:30:00] - sensor_beta reported temp: ERROR
LOG_START [2023-11-01T08:45:00] - sensor_alpha reported temp: 24.0
LOG_START [2023-11-01T08:45:00] - sensor_beta reported temp: 18.0
EOF

    chmod -R 777 /home/user
