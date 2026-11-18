#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.txt
ID X1 X2 Y
1 0 0 10.0
2 0 2 12.0
3 2 0 14.0
4 2 2 16.0
5 1 1 13.0
6 0 1 ?
7 2 1 ?
8 5 5 20.0
9 5 6 ?
EOF

    chmod -R 777 /home/user
