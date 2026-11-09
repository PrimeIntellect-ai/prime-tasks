#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
id,timestamp,sensor_value,is_anomaly
1,1000,45.5,0
2,1001,-5.0,0
3,1002,NA,1
4,1003,85.2,1
5,1004,12.0,0
6,1005,,1
7,1006,55.0,1
8,1007,22.1,0
9,1008,91.0,1
10,1009,10.0,0
11,1010,48.0,0
12,1011,75.0,1
13,1012,33.3,0
14,1013,62.5,1
15,1014,18.9,0
EOF

    chmod -R 777 /home/user
