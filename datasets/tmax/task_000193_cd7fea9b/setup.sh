#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,temperature,humidity
2023-10-01T12:34:15Z,S1,22.5,45.0
2023-10-01T12:34:45Z,S2,23.1,44.5
2023-10-01T12:34:50Z,S1,999.0,50.0
2023-10-01T12:35:05Z,S1,22.8,46.0
2023-10-01T12:35:10Z,S3,22.0,-5.0
2023-10-01T12:35:59Z,S2,23.0,47.0
2023-10-01T12:36:01Z,S1,,50.0
2023-10-01T12:36:15Z,S2,24.1,105.0
2023-10-01T12:37:00Z,S1,-45.0,20.0
2023-10-01T12:37:30Z,S2,-55.0,20.0
2023-10-01T12:37:45Z,S3,-40.0,25.0
EOF

    chmod -R 777 /home/user
