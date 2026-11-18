#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/citations.csv
source,target
1,2
1,3
2,4
3,4
4,5
5,6
6,7
8,4
9,8
10,9
11,10
12,5
13,12
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
