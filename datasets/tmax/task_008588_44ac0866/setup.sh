#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
1.2,2.4
2.1,3.9
3.5,6.1
4.2,8.0
5.8,11.2
6.1,12.5
7.3,14.0
8.9,17.2
9.5,18.8
10.1,20.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
