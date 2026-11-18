#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,d1_x,d1_y,d2_x,d2_y,d3_x,d3_y
2023-10-01T10:15:00Z,1.0,2.0,5.0,5.0,0.0,1.0
2023-10-01T10:45:00Z,2.0,2.0,-1.0,0.0,0.0,2.0
2023-10-01T11:05:00Z,0.0,0.0,3.0,4.0,-2.0,-2.0
2023-10-01T11:55:00Z,-3.0,-4.0,2.0,2.0,-1.0,0.0
2023-10-01T12:05:00Z,0.0,1.0,0.0,-1.0,3.0,4.0
EOF

    chmod -R 777 /home/user
