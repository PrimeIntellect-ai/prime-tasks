#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
sensor_id,timestamp,vehicle_count
A,2023-10-01T10:00:00Z,10
A,2023-10-01 07:00:00-04:00,15
A,2023-10-01T12:00:00Z,20
A,2023-10-01T12:00:00Z,20
A,2023-10-01T13:00:00Z,-5
A,2023-10-01T13:00:00+00:00,30
B,2023-10-01 10:00:00+00:00,50
B,2023-10-01T11:00:00Z,60
B,2023-10-01T12:00:00Z,70
C,2023-10-01T08:00:00-07:00,100
C,2023-10-01T15:30:00Z,120
EOF

    chmod -R 777 /home/user
