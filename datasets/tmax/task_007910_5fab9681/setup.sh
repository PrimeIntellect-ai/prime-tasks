#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/reports

    cat << 'EOF' > /home/user/wide_sensors.csv
timestamp,sensor_alpha,sensor_beta,sensor_gamma
2023-10-01T10:00:00,10.5,20.1,
2023-10-01T10:05:00,11.0,,30.5
2023-10-01T10:10:00,10.8,19.5,31.0
2023-10-01T10:15:00,11.2,19.8,30.2
2023-10-01T10:20:00,,20.5,29.8
EOF

    cat << 'EOF' > /home/user/template.md
# IoT Sensor Report: {SENSOR}

## Summary Statistics
* Highest recorded value: {MAX}
* Lowest recorded value: {MIN}
* Overall average: {AVG}

## Recent Activity
{TABLE}
EOF

    chmod -R 777 /home/user
