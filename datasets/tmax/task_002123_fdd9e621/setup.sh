#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/input.csv
id,value,category
1,12.5,X
2,-4.0,Y
3,8.1,Z
4,5.5,W
5,0.0,X
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
