#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
Time_stamp, SENSOR_x ,  sensor_Y,Sensor_Z
2023-10-01 10:00, 45.0 , 50.0, 40.0
2023-10-01 10:05 , 46.0, 49.0 ,41.0
2023-10-01 10:10,47.0,50.0,42.0
2023-10-01 10:15, 48.0, 51.0, 40.0
2023-10-01 10:20, 49.0, 52.0, 39.0
EOF

    chmod -R 777 /home/user
