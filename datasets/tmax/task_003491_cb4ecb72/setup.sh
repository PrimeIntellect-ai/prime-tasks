#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
user_id,age,income,score1,score2
U001,25,50000,0.8,0.2
U002,,60000,0.9,0.1
U003,40,-1000,0.5,0.5
U004,35,120000,0.85,0.25
U005,50,80000,0.2,0.8
EOF

    chown user:user /home/user/raw_data.csv
    chmod 644 /home/user/raw_data.csv

    chmod -R 777 /home/user
