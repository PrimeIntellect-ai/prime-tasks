#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo bc jq datamash
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user:user" | chpasswd
    usermod -aG sudo user

    mkdir -p /home/user/pipeline
    cat << 'EOF' > /home/user/pipeline/sensor_data.csv
timestamp,value
1,50
2,52
3,
4,48
5,100
6,49
7,51
8,
9,50
10,5
11,50
12,50
EOF

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
