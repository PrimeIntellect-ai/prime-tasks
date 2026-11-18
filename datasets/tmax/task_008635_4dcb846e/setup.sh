#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensors.csv
sensor_id,temp_c,pressure_hpa,vibration_hz
1,25.4,1013.2,50.1
2,28.1,1010.5,45.2
3,150.5,1005.0,10.0
4,-60.0,1100.0,20.0
5,30.0,1008.1,60.5
6,10.2,1020.5,
7,invalid,1015.0,30.0
8,35.5,1001.2,70.2
9,40.1,995.5,80.5
10,22.0,1015.8,40.0
11,26.5,1011.0,55.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
