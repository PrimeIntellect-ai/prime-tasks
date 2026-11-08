#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,temperature_c
2023-10-01 10:15:00,A101,22.5
2023-10-01 10:45:00,A101,23.5
2023-10-01 10:45:00,A101,23.5
2023-10-01 10:50:00,B202,15.0
2023-10-01 12:10:00,A101,24.0
2023-10-01 13:05:00,A101,25.0
2023-10-01 13:35:00,A101,25.6
EOF

    chmod -R 777 /home/user
