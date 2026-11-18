#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
sensor_id,x,y,variance
1,2.5,3.1,0.5
2,-1.0,4.0,1.2
invalid,row,here,0
3,2.0,2.8,0.8
4,2.2,3.0,-0.5
5,2.1,2.9,0.3
EOF

    chmod -R 777 /home/user
