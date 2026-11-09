#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sensor_log.csv
sensor_id,timestamp,temperature,notes
S1,2023-10-01 10:00:00-04:00,22.5,"Normal reading"
S2,2023-10-01T14:05:00Z,18.0,"Sensor restarted
Needs calibration"
S1,2023-10-01 14:30:00Z,45.0,"Spike detected"
S2,2023-10-01 11:10:00-04:00,18.5,"Normal"
S1,2023-10-01 12:00:00-04:00,44.0,"Still hot"
EOF

    chmod -R 777 /home/user
