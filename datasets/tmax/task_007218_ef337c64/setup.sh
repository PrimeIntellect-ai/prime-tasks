#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /home/user/sensor_data/data1.csv
sensor_id,timestamp,temperature,humidity
A1,2023/10/01 12:00:00,25.5,60
A1,2023/10/01 12:05:00,26.0,62
B2,01-10-2023 12:00:00,22.1,50
A1,2023/10/01 12:00:00,25.5,60
EOF

    cat << 'EOF' > /home/user/sensor_data/data2.json
[
  {"sensor_id": "B2", "timestamp": 1696161900000, "temperature": 22.5, "humidity": 52},
  {"sensor_id": "A1", "timestamp": 1696161600000, "temperature": 25.5, "humidity": 60},
  {"sensor_id": "C3", "timestamp": 1696162200000, "temperature": 28.0, "humidity": 70}
]
EOF

    chmod -R 777 /home/user
