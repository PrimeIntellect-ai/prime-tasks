#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_a,sensor_b,error_flag
1,52.5,14.2,0
2,NaN,15.1,0
3,11.0,4.0,1
4,49.5,13.8,0
5,50.2,14.1,0
6,51.0,14.0,0
7,48.0,13.5,0
8,55.0,NaN,0
9,53.2,14.5,0
10,47.1,13.1,1
EOF

    chmod -R 777 /home/user
