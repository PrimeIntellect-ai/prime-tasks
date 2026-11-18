#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/readings.csv
sensor_id,timestamp,temperature,humidity
SENS-01,2023-10-01T10:00:00Z,20.0,50.0
SENS-02,2023-10-01T10:00:00Z,22.0,45.0
SENS-02,2023-10-01T12:00:00Z,23.5,44.0
SENS-02,2023-10-01T12:00:00Z,24.0,42.0
SENS-03,2023-10-02T08:00:00Z,19.0,55.0
SENS-03,2023-10-02T07:00:00Z,25.0,60.0
EOF

    chmod -R 777 /home/user
