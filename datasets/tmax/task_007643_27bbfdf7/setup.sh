#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
timestamp,sensor_id,temperature,humidity
2023-10-01T00:00:00Z,S-101,22.5,45.0
2023-10-01T00:15:00Z,S-101,23.1,42.5
2023-10-01T00:30:00Z,S-101,21.8,48.0
2023-10-01T00:45:00Z,S-101,24.0,40.0
2023-10-01T01:00:00Z,S-101,25.2,38.5
2023-10-01T01:15:00Z,S-101,24.8,39.0
2023-10-01T01:30:00Z,S-101,22.9,44.0
2023-10-01T01:45:00Z,S-101,21.5,50.0
EOF

    chmod -R 777 /home/user
