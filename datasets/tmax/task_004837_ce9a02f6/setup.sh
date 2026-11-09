#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/customers.csv
id,age,income,spending_score
1,25,50000,60
2,-5,60000,70
3,36,74000,52
4,40,100000,90
5,twenty,50000,50
6,34,76000,49
7,22,20000,-5
8,50,60000,40
9,30,80000,
10,28,45000,105
EOF

    chmod -R 777 /home/user
