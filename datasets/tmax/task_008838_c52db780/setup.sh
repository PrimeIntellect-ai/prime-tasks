#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
sensor_id,timestamp,temperature
S1,2023-10-01T10:15:00Z,10.0
S1,2023-10-01T10:45:00Z,20.0
S1,2023-10-01T11:30:00Z,30.0
S1,2023-10-01T12:10:00Z,40.0
S1,2023-10-01T12:50:00Z,50.0
S1,2023-10-01T13:20:00Z,120.0
S1,2023-10-01T14:10:00Z,60.0
S2,2023-10-01T08:05:00Z,invalid
S2,2023-10-01T09:15:00Z,-60.0
S2,2023-10-01T10:00:00Z,5.0
S2,2023-10-01T11:00:00Z,10.0
EOF

    chmod -R 777 /home/user
