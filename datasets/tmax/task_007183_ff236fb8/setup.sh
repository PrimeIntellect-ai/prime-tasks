#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,value,label
1,10.0,0
2,10.2,0
3,10.1,0
4,NaN,0
5,10.3,0
6,15.5,1
7,10.1,0
8,10.2,0
9,ERROR,0
10,10.4,0
11,20.0,1
12,10.1,0
13,10.0,0
14,9.9,0
15,14.0,1
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
