#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensor_data.csv
sensor_id,timestamp,temperature
S1,2023-10-01 10:00:00,20.0
S1,2023-10-01 11:00:00,21.0
S1,2023-10-01 11:00:00,99.9
S1,2023-10-01 14:00:00,24.0
S1,2023-10-01 19:00:00,30.0
S2,2023-10-01 08:00:00,10.0
S2,2023-10-01 09:00:00,12.0
S2,2023-10-01 10:00:00,14.0
S2,2023-10-01 10:00:00,14.0
S2,2023-10-01 14:00:00,22.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
