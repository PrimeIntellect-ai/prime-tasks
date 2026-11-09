#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,measurement
1,10.5
2,NaN
3,12.2
4,-3.4
5,15.8
6,Infinity
7,20.0
8,-10.0
9,22.5
10,-Infinity
EOF

    chmod -R 777 /home/user
