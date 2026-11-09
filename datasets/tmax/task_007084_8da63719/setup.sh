#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
id,sensor_1,sensor_2,sensor_3,outcome
1,10.5,20.1,1,1
2,12.0,,0,0
3,55.0,30.0,1,1
4,15.2,25.4,1,0
5,14.8,22.0,0,1
6,11.1,19.5,1,1
7,13.4,21.0,0,0
8,60.2,35.0,1,0
9,10.0,18.5,1,1
10,12.5,,0,1
EOF

    chown user:user /home/user/sensor_data.csv
    chmod -R 777 /home/user
