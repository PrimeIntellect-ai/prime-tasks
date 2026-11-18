#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensor_1.csv
timestamp,sensor_id,temperature,humidity
2023/10/01 10:01:15,S1,20.0,45.0
2023/10/01 10:03:00,S1,22.0,50.0
2023/10/01 10:04:59,S1,24.0,55.0
2023/10/01 10:05:00,S1,25.0,60.0
2023/10/01 10:06:30,S1,-100.0,60.0
2023/10/01 10:08:00,S1,26.0,150.0
2023/10/01 10:11:00,S1,28.0,60.0
EOF

    cat << 'EOF' > /home/user/data/sensor_2.csv
timestamp,sensor_id,temperature,humidity
2023/10/01 10:02:10,S2,15.5,80.0
2023/10/01 10:04:10,S2,16.5,82.0
2023/10/01 10:05:10,S2,17.0,101.0
2023/10/01 10:07:15,S2,18.0,85.0
2023/10/01 10:09:59,S2,19.0,88.0
EOF

    chmod -R 777 /home/user
