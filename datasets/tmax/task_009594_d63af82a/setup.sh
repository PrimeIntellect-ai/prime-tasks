#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,category,v1,v2,v3,v4,v5
u1,A,1.5,-0.5,2.0,-1.0,1.0
u2,IGNORE,0.0,0.0,0.0,0.0,0.0
u3,B,-1.0,-2.0,0.5,0.0,2.0
u4,A,1.0,-1.0,1.0,-1.0,1.0
u5,A,5.0,5.0,5.0,5.0,5.0
u6,C,0.0,0.0,0.0,0.0,0.0
u7,B,2.0,2.0,2.0,2.0,2.0
u8,B,1.0,1.0,1.0,1.0,1.0
u9,C,1.0,-1.0,1.0,-1.0,1.0
EOF

    chmod -R 777 /home/user
