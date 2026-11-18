#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
id,sensor_x,sensor_y,target_val
1,10.0,2.0,15.0
2,8.0,0.0,10.0
3,15.0,3.0,20.0
4,20.0,4.0,25.0
5,-5.0,1.0,-10.0
6,12.0,2.0,18.0
7,9.0,-3.0,-8.0
8,0.0,5.0,2.0
9,14.0,0.0,-5.0
10,-10.0,-2.0,12.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
