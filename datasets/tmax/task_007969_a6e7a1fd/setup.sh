#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sensor_readings.csv
timestamp,sensor_id,temperature,status,notes
2023-10-01T10:00:00Z,S1,20.0,OK,All good
2023-10-01T10:01:00Z,S2,22.0,OK,"Multiline
note"
2023-10-01T10:02:00Z,S1,24.0,ERROR,Bad read
2023-10-01T10:03:00Z,S3,26.0,OK,Normal
2023-10-01T10:04:00Z,S2,not-a-num,OK,Testing
2023-10-01T10:05:00Z,S1,21.0,OK,Okay
2023-10-01T10:06:00Z,S3,18.0,OK,Cooling
2023-10-01T09:59:00Z,S5,10.0,OK,Early reading
EOF

    chmod -R 777 /home/user
