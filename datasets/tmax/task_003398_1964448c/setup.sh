#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_data.csv
id,sensor_id,reading_value,target_value
1,10,10.0,20.0
2,10,12.0,24.0
3,101,999.0,0.0
4,15,14.0,28.0
5,20,2000.0,0.0
6,20,,22.0
7,30,8.0,16.0
8,30,9.0,18.0
9,40,11.0,22.0
10,50,13.0,26.0
11,50,15.0,30.0
12,60,10.0,20.0
13,60,16.0,32.0
14,70,,24.0
EOF

    chmod -R 777 /home/user
