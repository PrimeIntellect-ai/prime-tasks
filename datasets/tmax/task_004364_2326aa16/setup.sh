#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > model.txt
PRIOR 0.6 0.4
TAG 10 0.8 0.1
TAG 15 0.7 0.2
TAG 20 0.1 0.9
TAG 25 0.2 0.8
TAG 30 0.9 0.1
TAG 35 0.1 0.95
EOF

    cat << 'EOF' > datasets.txt
1 10 15 30
2 20 25 35
3 10 30
4 20 25
5 15 30
6 35
7 10 15 30 99
8 20 25 35 99
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
