#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,age,income,score
1,25,50000,0.8
2,,60000,0.9
3,45,1500000,0.5
4,30,75000,0.7
5,22,-5000,0.2
6,50,120000,0.85
7,,100000,0.6
8,35,80000,0.95
9,28,90000,0.88
10,60,2000000,0.4
EOF

    chmod -R 777 /home/user
