#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_costs.csv
1,0,500,Corporate
2,1,100,Engineering
3,2,50,Engineering
4,1,200,Sales
5,2,75,Engineering
6,3,10,Engineering
7,1,50,Engineering
8,7,300,Engineering
EOF

    chmod 644 /home/user/raw_costs.csv
    chmod -R 777 /home/user
