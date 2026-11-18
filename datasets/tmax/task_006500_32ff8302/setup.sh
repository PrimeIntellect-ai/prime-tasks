#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow fastparquet

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
sensor_id,timestamp,value
temp_A,1672531260,70.0
temp_A,1672531440,72.0
press_B,2023-01-01T00:02:00Z,100.0
temp_A,1672531620,86.0
press_B,2023-01-01T00:06:00Z,102.0
press_B,2023-01-01T00:11:00Z,115.0
temp_A,1672532280,80.0
EOF

    chmod -R 777 /home/user
