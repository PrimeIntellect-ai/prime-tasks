#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/bus_gps.csv
timestamp,bus_id,x,y
2023-10-01T10:00:05Z,bus_1,100.0,200.0
2023-10-01T10:00:15Z,bus_1,120.0,200.0
2023-10-01T10:00:25Z,bus_1,140.0,210.0
2023-10-01T10:00:45Z,bus_1,180.0,210.0
EOF

    cat << 'EOF' > /home/user/data/targets.csv
point_id,x,y
point_A,110.0,240.0
point_B,130.0,205.0
point_C,500.0,500.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
