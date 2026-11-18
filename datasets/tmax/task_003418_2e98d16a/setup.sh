#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
sensor_id,date,metric,v0,v1,v2,v3,v4,v5
S1,2023-10-01,temp,12.5,10.0,15.2,18.1,16.0,14.2
S2,2023-10-01,temp,11.0,9.5,-999,17.5,15.5,13.0
S1,2023-10-01,humidity,80,85,70,60,65,75
S2,2023-10-01,humidity,82,88,72,62,68,-999
S3,2023-10-01,temp,14.0,12.0,16.0,20.0,18.0,15.0
EOF

    chmod -R 777 /home/user
