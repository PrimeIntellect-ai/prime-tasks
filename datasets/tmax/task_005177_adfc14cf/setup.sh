#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/records.csv
id,age,income,category
1,25,60000,A
2,45,120000,C
3,30,45000,B
4,50,80000,A
5,22,35000,C
EOF

    chmod -R 777 /home/user
