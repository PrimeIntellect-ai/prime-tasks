#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_export.csv
1,Alice,30,alice@example.com
2,Bob,17,bob@example.com
-3,Charlie,25,charlie@example.com
4,David,45,david.example.com
5,Eve,120,eve@example.com
6,Frank,121,frank@example.com
7,Grace,18,grace@example.com
invalid,Hank,40,hank@example.com
9,Ivy,bad,ivy@example.com
EOF

    chmod -R 777 /home/user
