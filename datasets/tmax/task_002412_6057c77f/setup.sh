#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk cargo build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
sensor_id,val_x,val_y,val_z,status
1,10.0,2.0,3.5,OK
2,1.0,1.0,1.0,FAIL
3,5.0,2.5,1.0,OK
4,0.0,0.0,0.0,OK
5,20.0,10.0,5.0,FAIL
6,8.0,4.0,2.0,OK
7,-3.0,1.5,0.5,OK
8,9.9,-9.9,0.0,ERROR
9,2.0,2.0,2.0,OK
EOF

    chmod -R 777 /home/user
