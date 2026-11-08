#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sensors.csv
sensor_id,location,sensor_type
1,Warehouse_A,Temperature
2,Warehouse_A,Humidity
3,Warehouse_B,Temperature
4,Warehouse_C,Temperature
EOF

    cat << 'EOF' > /home/user/data/readings.csv
timestamp,sensor_id,value
2023-10-01T00:00:00Z,1,20.0
2023-10-01T00:05:00Z,1,25.0
2023-10-01T00:00:00Z,2,45.0
2023-10-01T00:05:00Z,2,46.5
2023-10-01T00:00:00Z,3,30.0
2023-10-01T00:05:00Z,3,30.0
2023-10-01T00:00:00Z,4,10.0
2023-10-01T00:05:00Z,4,15.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
